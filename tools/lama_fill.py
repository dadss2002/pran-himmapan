#!/usr/bin/env python3
"""Free local AI fill (LaMa, Apache-2.0) for small map fixes - no PixelLab gen.

Model: lama_fp32.onnx (big-lama exported to ONNX by Carve-Photos), 512x512 fixed input.
  Download once (not committed, 208 MB), check the hash:
    curl -L -o /tmp/lama_dl/lama.onnx \
      https://github.com/neureps/carousel-fit-models/releases/download/lama-v1/lama-fp32-1faef5301d78.onnx
    sha256 1faef5301d78db7dda502fe59966957ec4b79dd64e16f03ed96913c7a4eb68d6
  pip install onnxruntime

Good at: removing lines/seams inside canopy, grass or dirt texture (continues the texture around).
Weak at: drawing shaped objects (a bush, a trunk) - it smooths them into flat blobs; use PixelLab
inpaint or copy a whole object from the same picture for those.
After the fill, new pixels are snapped to the palette of the ring around the mask so they stay crisp.

Usage: python3 tools/lama_fill.py <image.png> <mask.png 255=fill> <x0> <y0> <out.png> [model]
       (x0,y0 = top-left of the 512x512 window in the image)
"""
import sys
import numpy as np, cv2
from PIL import Image


def fill(img, mask, model="/tmp/lama_dl/lama.onnx", palette_colours=48):
    import onnxruntime as ort
    sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    x = img.astype(np.float32).transpose(2, 0, 1)[None] / 255.0
    m = (mask > 0).astype(np.float32)[None, None]
    out = np.clip(sess.run(None, {"image": x, "mask": m})[0][0].transpose(1, 2, 0), 0, 255)
    a = cv2.GaussianBlur((mask > 0).astype(np.float32), (0, 0), 1.5)[..., None]
    res = out * a + img.astype(np.float32) * (1 - a)
    ring = cv2.dilate((mask > 0).astype(np.uint8), np.ones((41, 41), np.uint8)) > 0
    ring &= ~(mask > 0)
    _, _, pal = cv2.kmeans(img[ring].reshape(-1, 3).astype(np.float32), palette_colours, None,
                           (3, 20, 1.0), 3, cv2.KMEANS_PP_CENTERS)
    mm = a[..., 0] > 0.01
    d = ((res[mm][:, None, :] - pal[None]) ** 2).sum(-1)
    res[mm] = pal[d.argmin(1)]
    return res.astype(np.uint8)


if __name__ == "__main__":
    src, msk, x0, y0, dst = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    model = sys.argv[6] if len(sys.argv) > 6 else "/tmp/lama_dl/lama.onnx"
    w = np.asarray(Image.open(src).convert("RGB")).copy()
    win = w[y0:y0 + 512, x0:x0 + 512]
    mask = np.asarray(Image.open(msk).convert("L"))
    w[y0:y0 + 512, x0:x0 + 512] = fill(win, mask, model)
    Image.fromarray(w).save(dst)
