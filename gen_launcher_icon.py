"""生成水滴形状的 App launcher icon。
输出多个密度：mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192
"""
from PIL import Image, ImageDraw, ImageFilter

# 各密度尺寸
sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# 颜色
BG = (255, 255, 255, 255)  # 白底
DROP_GRAD_TOP = (107, 200, 232, 255)  # 浅蓝
DROP_GRAD_BOT = (77, 184, 216, 255)   # 深蓝
EDGE = (60, 90, 130, 255)             # 边缘


def draw_drop(draw, size):
    """绘制水滴路径：上尖下圆"""
    w = size
    cx = w / 2
    # 水滴控制点
    top = (cx, w * 0.10)
    # 左侧贝塞尔近似：起点 top → 左中 (cx - 0.22w, 0.55w)
    # 用多段折线近似圆滑曲线
    pts = []
    # 简单方法：用 ellipse 做圆底 + 三角形做尖
    # 圆形底部
    rx = w * 0.30
    ry = w * 0.30
    cy = w * 0.62
    # 水滴主体：圆 + 上方尖头
    drop = [
        (cx, w * 0.10),            # 顶尖
        (cx - rx * 0.6, w * 0.40), # 左上
        (cx - rx, cy),             # 左中
        (cx - rx, cy + ry * 0.85), # 左下
        (cx, cy + ry),             # 底
        (cx + rx, cy + ry * 0.85), # 右下
        (cx + rx, cy),             # 右中
        (cx + rx * 0.6, w * 0.40), # 右上
        (cx, w * 0.10),            # 回顶尖
    ]
    # 用多边形 + 椭圆叠加更圆滑
    # 实际生成：用 polygon + ellipse 组合
    draw.polygon(drop, fill=DROP_GRAD_BOT)
    # 底部圆形让水滴更圆
    draw.ellipse(
        [cx - rx, cy - ry, cx + rx, cy + ry],
        fill=DROP_GRAD_BOT
    )
    # 添加内部高光
    draw.ellipse(
        [cx - rx * 0.5, cy - ry * 0.3, cx - rx * 0.05, cy + ry * 0.4],
        fill=(255, 255, 255, 180)
    )


def main():
    for folder, size in sizes.items():
        img = Image.new('RGBA', (size, size), BG)
        draw = ImageDraw.Draw(img)
        draw_drop(draw, size)
        # 轻微模糊让边更柔
        img = img.filter(ImageFilter.SMOOTH_MORE)
        img.save(f'app/android/app/src/main/res/{folder}/ic_launcher.png')
    print('OK')


if __name__ == '__main__':
    main()
