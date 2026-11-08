"""Per-ACCOUNT admission for ``/socket.io`` at the WSGI edge (audit N-2).

The gap this closes
-------------------
C-1 bounded the total number of ``/socket.io`` requests that may hold a Gunicorn
thread (``SlotCounter``) and the number of *connected* sockets per user
(``ConnectionRegistry``, enforced in the Socket.IO ``connect`` handler). But the
only identity check at the edge was "some validly signed token", so ONE account
could fill the *entire* edge limit with handshakes that never reach the
``connect`` handler (websockets that never send CONNECT, stalled long-polls,
connections kept after a refusal) and keep refilling it as the orphan reaper
closed them every ``SOCKETIO_AUTH_DEADLINE_SECONDS``. Every other user (and the
real-time features of the whole app) then got ``503 server_busy`` while REST
stayed up.

Design
------
* The account is identified at the very first moment, from the signature
  verified token claims (``sub``; ``jti`` for the negative cache). No database.
* :class:`AccountLedger` reserves a slot for the account *atomically*, before the
  request is handed to Socket.IO (so in-flight handshakes count), and releases
  it exactly when the WSGI response is closed (every exit path:
  disconnect, refusal, exception, orphan reaping, garbage collection).
* Over the per-account limit a *legitimate reconnect* (network switch) must not
  be blocked by its own stale transports, so the account's OLDEST evictable
  websocket (pending ones first, established ones last) is closed instead and
  the new request is admitted. Only when nothing is evictable (e.g. stalled
  long-polls) is the new request refused with ``503 too_many_connections``.
* Tokens that cannot be proven live at the edge are *restricted*: expired tokens
  (they must still reach ``connect`` so the F-36 ``token_expired`` -> refresh
  protocol is unchanged) and tokens/accounts the ``connect`` handler already
  found revoked / deleted / inactive (:class:`BadTokenCache`). They are charged
  to a tiny separate bucket, never to the account's real budget, so replaying
  somebody's old token cannot crowd out that person's live sockets, and the
  restricted buckets are capped globally.
* Requests that carry only an Engine.IO ``sid`` (long-poll GET/POST) are
  attributed to the account that created the session through the handshake
  environ python-socketio keeps; polling requests of an already CONNECTed
  session are never refused (they were admitted when the socket connected).
* Deliberately NO per-IP limit: carrier-grade NAT shares addresses.

State is per process, matching the supported single-worker deployment.
"""

from __future__ import annotations

import hashlib
import logging
import socket as _socket
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable

logger = logging.getLogger(__name__)

#: environ keys (the handshake environ is kept by python-socketio per session)
IDENTITY_KEY = "carnet.edge_identity"  # set by the authenticator for this request
ACCOUNT_KEY = "carnet.edge_account"  # (bucket, sub) of the session's creator
ESTABLISHED_KEY = "carnet.edge_established"  # set by ``connect`` on success
REFUSED_KEY = "carnet.edge_refused_at"  # set by ``connect`` on refusal

BUCKET_LIVE = "live"
BUCKET_RESTRICTED = "restricted"

REFUSE_ACCOUNT_BUSY = "too_many_connections"


@dataclass(frozen=True)
class Identity:
    """Signature-verified claims of the handshake token."""

    sub: str
    jti: str | None
    exp: float | None

    def expired(self, now: float) -> bool:
        return self.exp is None or float(self.exp) <= now


def shutdown_transport(raw: Any) -> None:
    """Unblock a request thread parked in ``ws.receive()`` (best effort)."""
    try:
        raw.shutdown(_socket.SHUT_RDWR)
    except (OSError, AttributeError):
        pass


# ---------------------------------------------------------------------------
# negative cache: tokens / accounts the connect handler proved dead
# ---------------------------------------------------------------------------
def _token_key(jti: str | None, raw_fallback: str | None) -> str | None:
    if jti:
        return "j:" + jti
    if raw_fallback:
        return "h:" + hashlib.sha256(raw_fallback.encode("utf-8")).hexdigest()[:32]
    return None


class BadTokenCache:
    """Bounded TTL set of revoked tokens and deleted/inactive accounts.

    Filled by the ``connect`` handler (which does the DB / blocklist check) so
    the edge can classify a replayed dead token without any I/O.
    """

    def __init__(self, clock: Callable[[], float] = time.monotonic, max_size: int = 4096):
        self._clock = clock
        self._max = max_size
        self._lock = threading.Lock()
        self._items: dict[str, float] = {}

    def _add(self, key: str | None, ttl: float) -> None:
        if not key or ttl <= 0:
            return
        now = self._clock()
        with self._lock:
            if len(self._items) >= self._max:
                for k in [k for k, until in self._items.items() if until <= now]:
                    self._items.pop(k, None)
                while len(self._items) >= self._max:  # still full: drop the oldest
                    self._items.pop(next(iter(self._items)), None)
            self._items[key] = now + ttl

    def add_token(self, jti: str | None, raw: str | None, ttl: float) -> None:
        self._add(_token_key(jti, raw), ttl)

    def add_account(self, sub: str | None, ttl: float) -> None:
        self._add(("a:" + sub) if sub else None, ttl)

    def _hit(self, key: str | None) -> bool:
        if not key:
            return False
        with self._lock:
            until = self._items.get(key)
            if until is None:
                return False
            if until <= self._clock():
                self._items.pop(key, None)
                return False
            return True

    def is_bad(self, identity: Identity, raw: str | None = None) -> bool:
        return self._hit(_token_key(identity.jti, raw)) or self._hit("a:" + identity.sub)

    def clear(self) -> None:
        with self._lock:
            self._items.clear()


#: shared with ``kk.socketio_handlers`` (filled) and the edge guard (read)
BAD_TOKENS = BadTokenCache()


# ---------------------------------------------------------------------------
# the ledger
# ---------------------------------------------------------------------------
@dataclass(eq=False)
class Ticket:
    account: str
    bucket: str
    is_ws: bool
    raw: Any
    state_env: dict | None
    created: float
    evicted: bool = False
    released: bool = False
    #: request of an already CONNECTed session: never refused by the account cap
    protected: bool = False
    meta: dict = field(default_factory=dict)

    @property
    def established(self) -> bool:
        env = self.state_env
        return bool(env and env.get(ESTABLISHED_KEY))


class AccountLedger:
    """Atomic per-account reservation of edge slots (see module docstring)."""

    def __init__(
        self,
        *,
        per_account: int,
        restricted_per_account: int,
        restricted_total: int,
        clock: Callable[[], float] = time.monotonic,
    ):
        #: 0 disables the per-account limit (restricted buckets stay enforced)
        self.per_account = per_account
        self.restricted_per_account = restricted_per_account
        self.restricted_total = restricted_total
        self._clock = clock
        self._lock = threading.Lock()
        self._live: dict[tuple[str, str], list[Ticket]] = {}
        self.evictions_total = 0
        self.refusals_total = 0

    # -- introspection -----------------------------------------------------
    def held(self, account: str, bucket: str = BUCKET_LIVE) -> int:
        with self._lock:
            return len(self._live.get((bucket, account), ()))

    def restricted_held(self) -> int:
        with self._lock:
            return sum(len(v) for (b, _a), v in self._live.items() if b == BUCKET_RESTRICTED)

    def accounts(self) -> int:
        with self._lock:
            return len(self._live)

    # -- reserve / release ---------------------------------------------------
    def reserve(
        self,
        account: str,
        bucket: str,
        *,
        is_ws: bool,
        raw: Any = None,
        state_env: dict | None = None,
        protected: bool = False,
    ) -> tuple[Ticket | None, list[Ticket]]:
        """``(ticket, victims)``. ``ticket`` is ``None`` when refused. ``victims``
        were removed from the ledger and their transports must be closed by the
        caller (outside any lock)."""
        key = (bucket, account)
        limit = self.per_account if bucket == BUCKET_LIVE else self.restricted_per_account
        now = self._clock()
        victims: list[Ticket] = []
        with self._lock:
            mine = self._live.setdefault(key, [])
            if not protected:
                need = 0
                if limit and len(mine) >= limit:
                    need = len(mine) - limit + 1
                if bucket == BUCKET_RESTRICTED and self.restricted_total:
                    total = sum(len(v) for (b, _a), v in self._live.items() if b == BUCKET_RESTRICTED)
                    if total >= self.restricted_total:
                        # the global restricted budget is full: only recycle our own
                        need = max(need, 1)
                if need:
                    cands = sorted(
                        (t for t in mine if t.is_ws and t.raw is not None),
                        key=lambda t: (t.established, t.created),
                    )
                    if len(cands) < need:
                        if not mine:
                            self._live.pop(key, None)
                        self.refusals_total += 1
                        return None, []
                    victims = cands[:need]
                    for v in victims:
                        v.evicted = True
                        mine.remove(v)
                    self.evictions_total += len(victims)
            t = Ticket(
                account=account, bucket=bucket, is_ws=is_ws, raw=raw,
                state_env=state_env, created=now, protected=protected,
            )
            mine.append(t)
            return t, victims

    def release(self, ticket: Ticket | None) -> None:
        if ticket is None:
            return
        key = (ticket.bucket, ticket.account)
        with self._lock:
            if ticket.released:
                return
            ticket.released = True
            lst = self._live.get(key)
            if lst is None:
                return
            try:
                lst.remove(ticket)
            except ValueError:
                pass  # evicted earlier
            if not lst:
                self._live.pop(key, None)

    def stalled(self, max_age: float) -> list[Ticket]:
        """Non-websocket requests in flight longer than ``max_age`` (a stalled
        handshake / poll body). Not removed: the owner releases on close."""
        if max_age <= 0:
            return []
        cutoff = self._clock() - max_age
        with self._lock:
            return [
                t
                for lst in self._live.values()
                for t in lst
                if not t.is_ws and t.raw is not None and t.created <= cutoff
            ]
