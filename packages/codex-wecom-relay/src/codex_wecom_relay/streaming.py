"""Pack whole assistant messages into bounded, editable WeCom bubbles."""

from dataclasses import dataclass


def split_utf8(text, budget):
    """Take the longest Unicode-code-point prefix fitting a UTF-8 byte budget."""
    prefix = text.encode("utf-8")[:budget].decode("utf-8", errors="ignore")
    if text and not prefix:
        raise ValueError("byte budget cannot fit the next Unicode character")
    return prefix, text[len(prefix) :]


@dataclass
class AssistantMessage:
    text: str = ""
    complete: bool = False
    offset: int = 0


class StreamReply:
    def __init__(self, send, stream_id, token, max_bytes):
        self.send = send
        self.base_id = stream_id
        self.footer = f"\n\n回复本条消息继续：`r#{token}`"
        self.max_bytes = max_bytes
        self.messages = []
        self.sequence = 1
        self.last_content = None

    def fits(self, body):
        return len((body + self.footer).encode("utf-8")) <= self.max_bytes

    def display(self, message):
        return message.text[message.offset :]

    def body(self, messages):
        body = ""
        for message in messages:
            text = self.display(message)
            if not text:
                continue
            body = body.rstrip("\r\n") + "\n\n" + text.lstrip("\r\n") if body else text
        return body

    def append(self, delta):
        if not delta:
            return
        if not self.messages or self.messages[-1].complete:
            self.messages.append(AssistantMessage())
        self.messages[-1].text += delta

    def complete(self, text=None):
        if not self.messages or self.messages[-1].complete:
            if not text:
                return
            self.append(text)
        elif text is not None:
            self.messages[-1].text = text
        self.messages[-1].complete = True

    async def emit(self, body, finish=False):
        if not self.fits(body):
            raise ValueError("stream content exceeds the UTF-8 byte limit")
        stream_id = self.base_id if self.sequence == 1 else f"{self.base_id}-{self.sequence}"
        await self.send(stream_id, body + self.footer, finish)
        self.last_content = body

    async def flush(self):
        body = self.body(self.messages)
        while not self.fits(body):
            # Retain the newest message in an editable bubble, even if complete.
            # Everything before it is known to be non-final and may be sealed.
            cut = 0
            for index in range(1, len(self.messages)):
                if not self.messages[index - 1].complete:
                    break
                if self.fits(self.body(self.messages[:index])):
                    cut = index
                else:
                    break
            if cut:
                await self.emit(self.body(self.messages[:cut]), finish=True)
                self.messages = self.messages[cut:]
            else:
                # A single assistant message exceeds the budget: hard-split its
                # text, preserving every Unicode code point and all remaining text.
                budget = self.max_bytes - len(self.footer.encode("utf-8"))
                prefix, _rest = split_utf8(self.display(self.messages[0]), budget)
                await self.emit(prefix, finish=True)
                self.messages[0].offset += len(prefix)
            self.sequence += 1
            self.last_content = None
            body = self.body(self.messages)
        if body and body != self.last_content:
            await self.emit(body)

    async def finish(self, drop_last=False, status=None):
        if drop_last and self.messages:
            self.messages.pop()
        await self.flush()
        body = self.body(self.messages)
        if not body:
            body = (
                "本轮已完成，最终回复见完成通知。" if drop_last else f"(本轮完成，status={status})"
            )
        await self.emit(body, finish=True)
