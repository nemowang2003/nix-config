import unittest

from codex_wecom_relay.streaming import StreamReply, split_utf8


class StreamingTests(unittest.IsolatedAsyncioTestCase):
    def reply(self, budget=160):
        frames = []

        async def send(stream_id, content, finish):
            frames.append((stream_id, content, finish))
            self.assertLessEqual(len(content.encode("utf-8")), budget)

        reply = StreamReply(send, "stream", "12345678", budget)
        return reply, frames

    @staticmethod
    def finished_bodies(reply, frames):
        return [content.removesuffix(reply.footer) for _, content, finish in frames if finish]

    async def test_exact_fit_then_backtrack_to_last_complete_message(self):
        reply, frames = self.reply()
        capacity = reply.max_bytes - len(reply.footer.encode("utf-8"))
        first = "甲" * (capacity // 3)
        first += "a" * (capacity - len(first.encode("utf-8")))
        reply.append(first)
        reply.complete()
        await reply.flush()
        self.assertEqual(len(frames[-1][1].encode("utf-8")), reply.max_bytes)
        self.assertFalse(frames[-1][2])
        reply.append("下一段")
        await reply.flush()
        await reply.finish()
        self.assertEqual(self.finished_bodies(reply, frames), [first, "下一段"])
        self.assertNotEqual(frames[0][0], frames[-1][0])

    async def test_overflow_retracts_partial_next_message_from_old_bubble(self):
        reply, frames = self.reply(200)
        first = "a" * 100
        reply.append(first)
        reply.complete()
        reply.append("b" * 5)
        await reply.flush()
        self.assertIn("b" * 5, frames[-1][1])
        reply.append("b" * 100)
        await reply.flush()
        await reply.finish()
        self.assertEqual(self.finished_bodies(reply, frames), [first, "b" * 105])
        self.assertEqual(frames[0][0], frames[1][0])
        self.assertEqual(frames[1][1], first + reply.footer)

    async def test_chooses_latest_fitting_complete_message(self):
        reply, frames = self.reply(200)
        reply.append("A" * 60)
        reply.complete()
        reply.append("B" * 60)
        reply.complete()
        reply.append("C" * 80)
        await reply.flush()
        await reply.finish()
        self.assertEqual(
            self.finished_bodies(reply, frames), ["A" * 60 + "\n\n" + "B" * 60, "C" * 80]
        )

    async def test_single_long_message_hard_split_loses_no_text(self):
        reply, frames = self.reply(128)
        text = '甲😀"\\é\n' * 100 + "结束"
        reply.append(text)
        await reply.flush()
        # The completed item's authoritative text must not restore sealed prefixes.
        reply.complete(text)
        await reply.finish()
        self.assertEqual("".join(self.finished_bodies(reply, frames)), text)
        self.assertGreater(len(self.finished_bodies(reply, frames)), 2)

    async def test_normalizing_boundary_newlines_does_not_split_deltas(self):
        reply, frames = self.reply()
        reply.append("我先检")
        reply.append("查配置。\n\n")
        reply.complete()
        reply.append("\n检查完成。")
        await reply.finish()
        self.assertEqual(self.finished_bodies(reply, frames), ["我先检查配置。\n\n检查完成。"])

    async def test_final_message_is_removed_only_from_editable_bubble(self):
        reply, frames = self.reply()
        reply.append("过程说明。")
        reply.complete()
        reply.append("最终答案。")
        reply.complete()
        await reply.flush()
        self.assertIn("最终答案", frames[-1][1])
        await reply.finish(drop_last=True)
        self.assertEqual(self.finished_bodies(reply, frames), ["过程说明。"])

    async def test_only_final_message_leaves_replyable_completion_hint(self):
        reply, frames = self.reply()
        reply.append("最终答案。")
        await reply.finish(drop_last=True)
        self.assertNotIn("最终答案。", frames[-1][1])
        self.assertIn("最终回复见完成通知", frames[-1][1])
        self.assertIn("r#12345678", frames[-1][1])

    async def test_empty_ticks_never_resend_and_final_frame_still_finishes(self):
        reply, frames = self.reply()
        await reply.flush()
        self.assertEqual(frames, [])
        reply.append("内容")
        await reply.flush()
        await reply.flush()
        self.assertEqual(len(frames), 1)
        await reply.finish()
        self.assertTrue(frames[-1][2])

    def test_utf8_split_counts_content_not_json_escapes(self):
        self.assertEqual(split_utf8('甲😀"\\', 7), ("甲😀", '"\\'))
        self.assertEqual(split_utf8("甲😀", 6), ("甲", "😀"))
