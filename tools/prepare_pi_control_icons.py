from pathlib import Path
from PIL import Image


ROOT = Path(r"E:\pi_control")
MASTER = ROOT / "assets" / "branding" / "pi_control_icon_1024.png"
IOS_SET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
BUILT_APP = ROOT / "artifacts" / "pi_control_release" / "Runner.app"
WEB = ROOT / "web"


def resize_into(source: Image.Image, target: Path, size: tuple[int, int]) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image = source.resize(size, Image.Resampling.LANCZOS).convert("RGB")
    image.save(target, format="PNG", optimize=True)


with Image.open(MASTER) as opened:
    master = opened.convert("RGB")

    for target in IOS_SET.glob("*.png"):
        with Image.open(target) as existing:
            resize_into(master, target, existing.size)

    resize_into(master, BUILT_APP / "AppIcon60x60@2x.png", (120, 120))
    resize_into(master, BUILT_APP / "AppIcon76x76@2x~ipad.png", (152, 152))

    resize_into(master, WEB / "favicon.png", (64, 64))
    resize_into(master, WEB / "icons" / "Icon-192.png", (192, 192))
    resize_into(master, WEB / "icons" / "Icon-512.png", (512, 512))
    resize_into(master, WEB / "icons" / "Icon-maskable-192.png", (192, 192))
    resize_into(master, WEB / "icons" / "Icon-maskable-512.png", (512, 512))

print("Updated iOS, built Runner.app, and web icons")
