#!/usr/bin/env python3
"""Render the JD pacing docs to print-ready PDFs.

Outputs (at repo root, gitignored):
  cheatsheet.pdf         — just the cheatsheet
  trail-log.pdf          — just the trail log
  JD-pacing-packet.pdf   — cheatsheet + trail-log combined

Usage:
  pip3 install markdown-pdf
  python3 tools/build-pdf.py

Letter landscape, 0.4" margins. Same CSS for all outputs so the cheatsheet
and trail log print as a matching set you can staple together.
"""

import os
from markdown_pdf import MarkdownPdf, Section

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CSS = """
@page { size: letter landscape; margin: 0.4in 0.35in; }
body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
       font-size: 8.5pt; line-height: 1.25; color: #111; }
h1 { font-size: 14pt; margin: 0 0 4pt 0; }
h2 { font-size: 10.5pt; margin: 6pt 0 3pt 0; border-bottom: 1px solid #999; }
h3 { font-size: 9.5pt; margin: 4pt 0 2pt 0; }
table { border-collapse: collapse; width: 100%; margin: 2pt 0 4pt 0;
        font-size: 7.5pt; }
th, td { border: 1px solid #aaa; padding: 2pt 3pt; text-align: left;
         vertical-align: top; }
th { background: #eee; font-weight: 600; }
hr { border: 0; border-top: 1px solid #ccc; margin: 6pt 0; }
strong { font-weight: 700; }
ul { margin: 2pt 0 4pt 16pt; padding: 0; }
li { margin: 1pt 0; }
"""


def read(name):
    with open(os.path.join(ROOT, name)) as f:
        return f.read()


def build(name, sections, title):
    pdf = MarkdownPdf(toc_level=0, optimize=True)
    for md in sections:
        pdf.add_section(Section(md, toc=False), user_css=CSS)
    pdf.meta["title"]  = title
    pdf.meta["author"] = "Bob Sanford"
    out = os.path.join(ROOT, name)
    pdf.save(out)
    print(f"  {name}")
    return out


def main():
    cheatsheet = read("cheatsheet.md")
    traillog   = read("trail-log.md")

    print("Building PDFs:")
    build("cheatsheet.pdf",       [cheatsheet],            "JD Pacing Cheatsheet")
    build("trail-log.pdf",        [traillog],              "JD Trail Log")
    build("JD-pacing-packet.pdf", [cheatsheet, traillog],  "JD Pacing Packet")
    print(f"\nAll outputs in: {ROOT}")
    print("(PDFs are gitignored — regenerate any time with this script.)")


if __name__ == "__main__":
    main()
