import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest


spec = importlib.util.spec_from_file_location(
    "keyboard_control", Path(__file__).resolve().parents[1] / "keyboard-control.py"
)
keyboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keyboard)


class KeyboardTests(unittest.TestCase):
    @staticmethod
    def message():
        return SimpleNamespace(header=SimpleNamespace(stamp=None))

    def test_each_action_has_one_press_and_release_with_neutral_axes(self):
        for key, expected_button in (("1", 4), ("2", 3), ("3", 2), ("4", 5)):
            with self.subTest(key=key):
                messages = []
                publisher = SimpleNamespace(publish=messages.append)
                keyboard.send_button(publisher, self.message, lambda: 123,
                                     keyboard.KEYS[key][0], sleep=lambda _: None)
                self.assertEqual(len(messages), 3)
                self.assertEqual(sum(messages[0].buttons), 0)
                self.assertEqual(sum(messages[1].buttons), 1)
                self.assertEqual(messages[1].buttons[expected_button], 1)
                self.assertEqual(sum(messages[2].buttons), 0)
                for message in messages:
                    self.assertEqual(len(message.buttons), 11)
                    self.assertEqual(message.axes, [0, 0, 1, 0, 0, 1, 0, 0])
                    self.assertEqual(message.header.stamp, 123)

    def test_interrupted_press_still_releases_button(self):
        messages = []

        def sleep(seconds):
            if len(messages) == 2:
                raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            keyboard.send_button(SimpleNamespace(publish=messages.append),
                                 self.message, lambda: 0, 5, sleep=sleep)
        self.assertEqual(messages[1].buttons[5], 1)
        self.assertEqual(sum(messages[-1].buttons), 0)


if __name__ == "__main__":
    unittest.main()
