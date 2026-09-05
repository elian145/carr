"""C-02: unit tests for `chat_realtime.deliver_message()`.

`deliver_message()` is the shared post-commit delivery helper for the five REST
chat-send endpoints (`kk/routes/chat.py`). It must be called only *after* a
`Message` row has been durably committed, and none of its three side effects
(Socket.IO emit, `Notification` row, FCM push) may ever:

  - raise out of the function,
  - roll back or otherwise touch the already-committed `Message`, or
  - leave the SQLAlchemy session broken for the caller.

These tests exercise `deliver_message()` in isolation (mocked collaborators),
independent of the Flask app/DB fixtures used by the REST integration tests in
`test_chat_rest_delivery.py`.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from kk import chat_realtime


def _make_msg(content: str = "hello", car_public_id: str | None = "car-pub-1"):
    car = SimpleNamespace(public_id=car_public_id) if car_public_id is not None else None
    msg = SimpleNamespace(
        id=99,
        public_id="msg-pub-1",
        content=content,
        car=car,
    )
    msg.to_dict = lambda: {"id": msg.public_id, "content": msg.content}
    return msg


def _make_sender():
    return SimpleNamespace(id=1, public_id="sender-pub", first_name="Sen", last_name="Der")


def _make_receiver(fcm_token: str | None = "fcm-token-123"):
    return SimpleNamespace(id=2, public_id="receiver-pub", firebase_token=fcm_token)


def _patched():
    """Patch every collaborator `deliver_message` touches; returns the mocks."""
    return (
        patch.object(chat_realtime, "emit_message_to_participants"),
        patch.object(chat_realtime, "Notification"),
        patch.object(chat_realtime, "db"),
        patch.object(chat_realtime, "send_push"),
    )


def test_deliver_message_success_emits_socket_notification_and_push():
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        push_mock.return_value = True
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

    # Socket.IO: exactly one `new_message` emit to the two participants.
    emit_mock.assert_called_once()
    args, kwargs = emit_mock.call_args
    assert args[0] == "new_message"
    assert kwargs["message"] is msg
    assert kwargs["sender"] is sender
    assert kwargs["receiver"] is receiver

    # Notification: exactly one row constructed, added, and committed.
    notif_cls.assert_called_once()
    _, notif_kwargs = notif_cls.call_args
    assert notif_kwargs["user_id"] == receiver.id
    assert notif_kwargs["notification_type"] == "message"
    assert notif_kwargs["data"]["car_id"] == "car-pub-1"
    assert notif_kwargs["data"]["sender_id"] == sender.public_id
    db_mock.session.add.assert_called_once_with(notif_cls.return_value)
    db_mock.session.commit.assert_called_once()

    # Push: exactly one send_push call using the receiver's token.
    push_mock.assert_called_once()
    push_args, push_kwargs = push_mock.call_args
    assert push_args[0] == "fcm-token-123"
    assert push_kwargs["data"]["type"] == "chat_message"


def test_deliver_message_socket_failure_does_not_block_notification_or_push():
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        emit_mock.side_effect = RuntimeError("socket transport exploded")
        # Must not raise.
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        db_mock.session.commit.assert_called_once()
        push_mock.assert_called_once()


def test_deliver_message_notification_failure_does_not_affect_message_or_break_session():
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        db_mock.session.commit.side_effect = RuntimeError("db exploded on notification commit")
        # Must not raise, and must not attempt to delete/rollback the Message
        # (deliver_message never references msg deletion/rollback of a prior
        # transaction — only the pending Notification insert is rolled back).
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        # Socket emit still attempted.
        emit_mock.assert_called_once()
        # Notification commit was attempted and failed...
        db_mock.session.commit.assert_called_once()
        # ...and the session was rolled back to stay usable, exactly once.
        db_mock.session.rollback.assert_called_once()
        # Push is a separate try/except block and must still be attempted.
        push_mock.assert_called_once()


def test_deliver_message_push_failure_does_not_propagate():
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        push_mock.side_effect = RuntimeError("fcm exploded")
        # Must not raise.
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        emit_mock.assert_called_once()
        db_mock.session.commit.assert_called_once()
        push_mock.assert_called_once()


def test_deliver_message_skips_push_when_receiver_has_no_fcm_token():
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver(fcm_token=None)

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        emit_mock.assert_called_once()
        db_mock.session.commit.assert_called_once()
        push_mock.assert_not_called()


def test_deliver_message_exactly_one_notification_row_and_one_push_call():
    """Explicit no-duplicate guard: a single delivery call must not fan out."""
    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        assert notif_cls.call_count == 1
        assert db_mock.session.add.call_count == 1
        assert db_mock.session.commit.call_count == 1
        assert push_mock.call_count == 1
        assert emit_mock.call_count == 1


def test_deliver_message_returns_the_payload_it_serialized_exactly_once():
    """C-10 perf fix: `deliver_message()` must return the same serialized
    payload it built internally (and emitted over Socket.IO) so REST callers
    can reuse it for their HTTP response instead of calling `msg.to_dict()`
    a second time. For chat media, each `to_dict()` call re-presigns every
    private-bucket attachment via an R2 subprocess call, so calling it twice
    per send would presign the same attachment(s) twice for no reason.
    """
    msg = _make_msg()
    expected_payload = {"id": msg.public_id, "content": msg.content}
    to_dict_mock = MagicMock(return_value=expected_payload)
    msg.to_dict = to_dict_mock
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit, p_notif, p_db, p_push:
        result = chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

    # `to_dict()` (and therefore any attachment presigning inside it) must
    # only ever run ONCE per delivery, regardless of how many collaborators
    # (socket emit, push body, HTTP response reuse) need the payload.
    to_dict_mock.assert_called_once()
    assert result == expected_payload
    assert result is to_dict_mock.return_value


def test_deliver_message_handles_message_without_car():
    """Group/attachment messages may not always have a resolvable car; must not crash."""
    msg = _make_msg(car_public_id=None)
    sender = _make_sender()
    receiver = _make_receiver()

    p_emit, p_notif, p_db, p_push = _patched()
    with p_emit as emit_mock, p_notif as notif_cls, p_db as db_mock, p_push as push_mock:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

        _, notif_kwargs = notif_cls.call_args
        assert notif_kwargs["data"]["car_id"] is None
        push_mock.assert_called_once()
