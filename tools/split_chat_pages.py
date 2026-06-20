"""Split lib/pages/chat_pages.dart into part files and conversation extensions."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
src_path = REPO / "lib/pages/chat_pages.dart"
lines = src_path.read_text(encoding="utf-8").splitlines()

class_parts = [
    ("chat_widgets.dart", 289, 677),
    ("chat_list_page.dart", 677, 1020),
    ("chat_notifications_page.dart", 4282, len(lines)),
]

conversation_extensions = [
    ("chat_conversation_history.dart", "ChatConversationHistory", 1133, 1772),
    ("chat_conversation_transport.dart", "ChatConversationTransport", 1772, 2261),
    ("chat_conversation_actions.dart", "ChatConversationActions", 2261, 2525),
    ("chat_conversation_composer_ui.dart", "ChatConversationComposerUi", 2525, 2927),
    ("chat_conversation_message_ui.dart", "ChatConversationMessageUi", 2960, 3555),
    ("chat_conversation_layout.dart", "ChatConversationLayout", 3558, 3664),
]

layout_consts = """const double _kOutgoingMetaMinGap = 14;
const double _kBubbleHorizontalPadding = 32;
"""

out_dir = REPO / "lib/pages/chat"
out_dir.mkdir(exist_ok=True)

part_lines = []
ignore_header = (
    "// ignore_for_file: invalid_use_of_protected_member, "
    "library_private_types_in_public_api\n\n"
)

for fname, start, end in class_parts:
    body = "\n".join(lines[start:end])
    (out_dir / fname).write_text(
        f"part of '../chat_pages.dart';\n\n{body}\n",
        encoding="utf-8",
    )
    part_lines.append(f"part 'chat/{fname}';")

for fname, ext_name, start, end in conversation_extensions:
    body = "\n".join(lines[start:end])
    if fname == "chat_conversation_history.dart":
        # WidgetsBindingObserver override must stay on the State class, not an extension.
        body = "\n".join(lines[start:1368] + lines[1375:end])
    body = body.replace("_perPage", "_ChatConversationPageState._perPage")
    prefix = layout_consts + "\n" if fname == "chat_conversation_layout.dart" else ""
    part_text = (
        f"part of '../chat_pages.dart';\n\n"
        f"{ignore_header}"
        f"{prefix}"
        f"extension {ext_name} on _ChatConversationPageState {{\n"
        f"{body}\n"
        f"}}\n"
    )
    (out_dir / fname).write_text(part_text, encoding="utf-8")
    part_lines.append(f"part 'chat/{fname}';")

top_level = "\n".join(lines[27:289])
conversation_widget = "\n".join(lines[1020:1044])
conv_fields = "\n".join(lines[1046:1090])
conv_init = "\n".join(lines[1090:1133])
conv_lifecycle = "\n".join(lines[1368:1375])
conv_dispose = "\n".join(lines[2927:2956])
conv_key_helper = "\n".join(lines[2956:2960])
conv_build = "\n".join(lines[3664:4280])

header = "\n".join(lines[0:27]) + "\n"
parts_block = "\n".join(part_lines)

main = f"""{header}
{parts_block}

{top_level}

{conversation_widget}

class _ChatConversationPageState extends State<ChatConversationPage>
    with WidgetsBindingObserver {{
{conv_fields}
{conv_init}
{conv_lifecycle}
{conv_dispose}
{conv_key_helper}
{conv_build}
}}
"""

src_path.write_text(main, encoding="utf-8")
print(f"main: {len(main.splitlines())} lines")
for path in sorted(out_dir.glob("*.dart")):
    print(f"  {path.name}: {len(path.read_text(encoding='utf-8').splitlines())} lines")
