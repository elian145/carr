"""Unit tests for chat read-receipt helper (M-14)."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from kk import chat_realtime


def test_mark_messages_read_for_viewer_noop_without_args():
    assert chat_realtime.mark_messages_read_for_viewer(None, None) == {
        "marked": 0,
        "message_ids": [],
    }


def test_mark_messages_read_emits_to_senders():
    car = SimpleNamespace(id=1, public_id="car-1")
    viewer = SimpleNamespace(id=10, public_id="viewer-1")
    sender = SimpleNamespace(id=20, public_id="sender-1")
    msg = SimpleNamespace(
        id=99,
        public_id="msg-1",
        sender_id=20,
        receiver_id=10,
        is_read=False,
        is_deleted=False,
        created_at=None,
    )

    query = MagicMock()
    query.filter.return_value = query
    query.order_by.return_value = query
    query.all.return_value = [msg]
    query.update.return_value = 1

    user_query = MagicMock()
    user_query.filter.return_value = user_query
    user_query.all.return_value = [sender]

    with (
        patch.object(chat_realtime, "Message") as Message,
        patch.object(chat_realtime, "User") as User,
        patch.object(chat_realtime, "db") as db,
        patch.object(chat_realtime, "emit_to_user_rooms") as emit_rooms,
    ):
        Message.query = query
        User.query = user_query
        result = chat_realtime.mark_messages_read_for_viewer(car, viewer)

    assert result["marked"] == 1
    assert result["message_ids"] == ["msg-1"]
    db.session.commit.assert_called_once()
    emit_rooms.assert_called_once()
    args, _kwargs = emit_rooms.call_args
    assert args[0] == "messages_read"
    assert args[1]["car_id"] == "car-1"
    assert args[1]["reader_id"] == "viewer-1"
    assert args[1]["message_ids"] == ["msg-1"]
    assert args[2] is sender
