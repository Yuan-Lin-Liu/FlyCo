#!/usr/bin/env python3
"""Keyboard equivalents of FlyCo's task triggers; run in its ROS container."""

import argparse
import os
import select
import sys
import termios
import time
import tty


KEYS = {
    "1": (4, "初始化 / LB。等待模块准备完成，再按 2。"),
    "2": (3, "初始飞行 / Y。等待飞行稳定，在 FlyCo-UI 选目标并发送提示，再按 3。"),
    "3": (2, "启用规划服务 / X。等待目标分割、点云和规划数据准备完成，再按 4。"),
    "4": (5, "自主扫描 / RB。请在 RViz 和 AirSim 观察轨迹及飞行。"),
}
HELP = """
FlyCo 键盘触发器（请让本终端获得键盘焦点）
  1  初始化模块          [手柄 LB]
  2  开始初始飞行        [手柄 Y]
     然后到 FlyCo-UI 框选/点选目标，点击 send points
     可选：输入目标描述，点击 send text
  3  启用规划服务        [手柄 X]
  4  开始自主扫描        [手柄 RB]
  h  显示帮助
  q  退出键盘程序（不会停止正在执行的飞行）
每一步单独按一次，等待系统就绪再执行下一步。
启动本程序不会自动起飞；切回本终端才会接收数字键。
"""


def send_button(publisher, message_type, stamp, button, sleep=time.sleep):
    def publish(active=None):
        message = message_type()
        message.header.stamp = stamp()
        # Callbacks index axes[7] and buttons[5] without checking length.
        # Released trigger axes are +1, matching the Xbox joystick layout.
        message.axes = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        message.buttons = [0] * 11
        if active is not None:
            message.buttons[active] = 1
        publisher.publish(message)

    publish()  # Ensure a rising edge even after a previous interrupted press.
    sleep(0.1)
    try:
        publish(button)
        sleep(0.15)
    finally:
        publish()  # Release, including when Ctrl-C interrupts the pulse.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check ROS connectivity without sending controls")
    options = parser.parse_args()
    if not options.check and not sys.stdin.isatty():
        parser.error("Run in an interactive terminal (docker exec -it).")

    import rospy
    from sensor_msgs.msg import Joy

    rospy.init_node("flyco_keyboard", anonymous=True, disable_signals=True)
    publisher = rospy.Publisher("/joy", Joy, queue_size=10, latch=False)
    deadline = time.monotonic() + 5
    while publisher.get_num_connections() == 0 and time.monotonic() < deadline:
        if rospy.is_shutdown():
            return 1
        time.sleep(0.1)
    if publisher.get_num_connections() == 0:
        print("未检测到 /joy 订阅者。请先启动 FlyCo 并检查规划节点。", file=sys.stderr)
        return 1
    print(f"已连接 /joy，订阅连接数：{publisher.get_num_connections()}。", flush=True)
    if options.check:
        print("连接检查通过；未发送任何控制指令。", flush=True)
        return 0

    print(HELP, flush=True)
    fd = sys.stdin.fileno()
    settings = termios.tcgetattr(fd)
    last_key, last_time = None, 0.0
    try:
        tty.setcbreak(fd)
        while not rospy.is_shutdown():
            readable, _, _ = select.select([fd], [], [], 0.2)
            if not readable:
                continue
            data = os.read(fd, 1)
            if not data:
                break
            key = data.decode("ascii", errors="ignore").lower()
            if key in ("q", "\x04"):
                break
            if key == "h":
                print(HELP, flush=True)
            elif key in KEYS:
                now = time.monotonic()
                if key == last_key and now - last_time < 1.0:
                    continue
                if publisher.get_num_connections() == 0:
                    print("/joy 订阅者已断开，未发送指令。", flush=True)
                    continue
                button, description = KEYS[key]
                send_button(publisher, Joy, rospy.Time.now, button)
                last_key, last_time = key, time.monotonic()
                print(f"已发送：{description}", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, settings)
        rospy.signal_shutdown("Keyboard controller closed")
    print("键盘程序已退出；不会停止正在执行的飞行。", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
