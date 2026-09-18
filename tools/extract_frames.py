"""从官方演示视频中抽取帧，作为像素级对齐的参照物。"""
import os
import sys
import cv2

SRC = r"D:\2026\ai\2\地产风云_web\.out\reference\demo.mp4"
OUT = r"D:\2026\ai\2\地产风云_web\.out\reference\frames"
os.makedirs(OUT, exist_ok=True)

cap = cv2.VideoCapture(SRC)
if not cap.isOpened():
    print("无法打开视频")
    sys.exit(1)

fps = cap.get(cv2.CAP_PROP_FPS) or 0
total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
dur = total / fps if fps else 0
print(f"分辨率 {w}x{h}  fps={fps:.2f}  帧数={total}  时长={dur:.1f}s")

# 每 0.5 秒抽一帧
step = max(1, int(round(fps * 0.5)))
saved = 0
prev_small = None
import numpy as np

i = 0
while True:
    ok = cap.grab()
    if not ok:
        break
    if i % step == 0:
        ok, frame = cap.retrieve()
        if not ok:
            break
        small = cv2.resize(frame, (32, 56))
        # 与上一保存帧差异过小则跳过（去重）
        if prev_small is None or np.mean(cv2.absdiff(small, prev_small)) > 2.0:
            name = os.path.join(OUT, f"f{i:05d}.jpg")
            # 注意：cv2.imwrite 在 Windows 上无法处理含中文的路径，改用 imencode + 文件写
            ok_enc, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
            if ok_enc:
                with open(name, "wb") as fp:
                    fp.write(buf.tobytes())
                prev_small = small
                saved += 1
    i += 1

cap.release()
print(f"已保存 {saved} 帧到 {OUT}")
