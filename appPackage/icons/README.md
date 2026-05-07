# 아이콘 파일 안내

이 디렉터리에 다음 두 파일을 직접 추가하세요. **Phase 3.5 패키징 단계 전 필수**입니다.

| 파일 | 크기 | 형식 | 비고 |
|---|---|---|---|
| `color.png` | **192 × 192** | PNG | 컬러 풀 아이콘. 배경 포함 가능 |
| `outline.png` | **32 × 32** | PNG | 단색 흰색 + **투명 배경**. 그렇지 않으면 검증 실패 |

> 📁 두 파일은 패키징 시 zip의 **루트(매니페스트와 같은 위치)** 에 들어가야 합니다.
> 따라서 실제 패키징 직전에 `appPackage/color.png`, `appPackage/outline.png`로 복사하거나,
> 처음부터 `appPackage/`에 두는 것을 권장합니다. 이 `icons/` 폴더는 안내 + 참고용입니다.

## 빠른 임시 아이콘 (워크숍용)

학습 목적이라면 단색 placeholder도 충분합니다. 예시:

```powershell
# Python Pillow가 설치되어 있다면 (pip install pillow)
python - <<'PY'
from PIL import Image, ImageDraw

# color.png — 192x192 파란 배경에 흰색 "FAQ" 텍스트
img = Image.new("RGB", (192, 192), color=(0, 120, 212))
ImageDraw.Draw(img).text((50, 80), "FAQ", fill=(255, 255, 255))
img.save("appPackage/color.png")

# outline.png — 32x32 흰색 외곽선 (투명 배경)
img = Image.new("RGBA", (32, 32), color=(0, 0, 0, 0))
draw = ImageDraw.Draw(img)
draw.rectangle([2, 2, 29, 29], outline=(255, 255, 255, 255), width=2)
img.save("appPackage/outline.png")
PY
```

또는 [Teams 앱 아이콘 가이드](https://learn.microsoft.com/microsoftteams/platform/concepts/build-and-test/apps-package#app-icons)의 샘플을 사용해도 됩니다.

## 패키징 시 주의

- 파일명은 매니페스트의 `icons.color`, `icons.outline` 값과 정확히 일치해야 합니다 (대소문자 포함)
- zip의 **루트**에 manifest.json/color.png/outline.png가 있어야 합니다 (하위 폴더 X)
