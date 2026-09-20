"""Build the Jevalyn logo assets.

The mark is the gem's own idea drawn literally: a probability distribution over
four options, and a threshold rule across it. One bar clears the rule and is
picked out in jade; the rest sit under it in ink. That is what a Jev choice
answer is and what `confidence_threshold` does to it.

PIL has no vector renderer, so everything is drawn at SCALE and downsampled --
which antialiases better than PIL's own shape smoothing.

    python docs/assets/build_logo.py
"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np

SCALE = 4

INK_LIGHT = (33, 40, 60)       # near-black navy, for a white README
INK_DARK = (223, 229, 241)     # same mark, legible on GitHub's dark theme
JADE = (45, 184, 138)          # the accent: "this one cleared the bar"
MUTED_LIGHT = (33, 40, 60, 140)
MUTED_DARK = (223, 229, 241, 140)

AVENIR = "/System/Library/Fonts/Avenir Next.ttc"
DEMI, MEDIUM = 2, 5

# Heights as a fraction of the mark. Deliberately not a flat distribution and
# not a spike either -- a real answer with one clear winner and a live runner-up.
BARS = (0.34, 0.58, 1.00, 0.26)
THRESHOLD = 0.76               # where the confidence floor crosses


def rounded_bar(draw, x, y_top, y_bottom, width, fill):
    """A bar with a round cap at the top and a square foot on the baseline."""
    radius = width / 2
    draw.rounded_rectangle([x, y_top, x + width, y_bottom], radius=radius, fill=fill)
    draw.rectangle([x, y_bottom - radius, x + width, y_bottom], fill=fill)


def draw_mark(size, ink, muted):
    """The distribution-and-threshold mark, square, on transparency."""
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = s * 0.10
    inner = s - pad * 2
    bar_w = inner * 0.185
    gap = (inner - bar_w * len(BARS)) / (len(BARS) - 1)
    baseline = pad + inner

    rule_y = pad + inner * (1 - THRESHOLD)

    for i, height in enumerate(BARS):
        x = pad + i * (bar_w + gap)
        top = baseline - inner * height
        clears = height > THRESHOLD
        rounded_bar(draw, x, top, baseline, bar_w, JADE if clears else muted)

    # The threshold rule sits on top of the bars it is judging, and runs a little
    # past them on both sides so it reads as a rule rather than as a fifth bar.
    overhang = inner * 0.035
    rule_h = max(2, s * 0.030)
    draw.rounded_rectangle(
        [pad - overhang, rule_y - rule_h / 2, pad + inner + overhang, rule_y + rule_h / 2],
        radius=rule_h / 2, fill=ink
    )

    return img.resize((size, size), Image.LANCZOS)


def tracked_text(draw, xy, text, font, fill, tracking):
    """PIL has no letter-spacing, so set the line a glyph at a time."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking


def tracked_width(draw, text, font, tracking):
    return sum(draw.textlength(c, font=font) for c in text) + tracking * (len(text) - 1)


def build(tagline, out_path, square_path, ink, muted):
    mark_size = 190
    mark = draw_mark(mark_size, ink, muted)

    word_font = ImageFont.truetype(AVENIR, 88, index=DEMI)
    tag_font = ImageFont.truetype(AVENIR, 25, index=DEMI)
    word_tracking, tag_tracking = 1.5, 4.6

    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    word_w = tracked_width(probe, "Jevalyn", word_font, word_tracking)
    tag_w = tracked_width(probe, tagline, tag_font, tag_tracking)

    w_ascent, w_descent = word_font.getmetrics()
    t_ascent, t_descent = tag_font.getmetrics()

    pad = 46
    gap_mark, gap_tag = 6, 20

    width = int(max(mark.width, word_w, tag_w) + pad * 2)
    height = int(pad + mark.height + gap_mark + w_ascent + w_descent + gap_tag
                 + t_ascent + t_descent + pad)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    y = pad
    canvas.alpha_composite(mark, ((width - mark.width) // 2, int(y)))
    y += mark.height + gap_mark

    tracked_text(draw, ((width - word_w) / 2, y), "Jevalyn", word_font, ink, word_tracking)
    y += w_ascent + w_descent + gap_tag

    tracked_text(draw, ((width - tag_w) / 2, y), tagline, tag_font, JADE, tag_tracking)

    # Not trimmed: the padding is the layout. A logo flush against its own bounding
    # box has nowhere to breathe next to a heading.
    canvas.save(out_path)

    # Square mark alone, for a favicon or an avatar where the wordmark is unreadable.
    side = 512
    square = draw_mark(side, ink, muted)
    square.save(square_path)

    return canvas.size, square.size


if __name__ == "__main__":
    TAGLINE = "THE DECISION LAYER FOR YOUR RAILS APP"
    print("light:", build(TAGLINE, "docs/assets/logo.png", "docs/assets/logo-square.png",
                          INK_LIGHT, MUTED_LIGHT))
    print("dark: ", build(TAGLINE, "docs/assets/logo-dark.png", "docs/assets/logo-square-dark.png",
                          INK_DARK, MUTED_DARK))
