# テスト用PDFの生成スクリプト（reportlab）。python3 test/fixtures/files/make_pdfs.py
import os
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
# ToUnicode 付きで埋め込める TTF を使う（CID フォントだと pdf-reader で文字が取れない）
pdfmetrics.registerFont(TTFont('JP', '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf'))
here = os.path.dirname(__file__)
Z = '０１２３４５６７８９'  # このフォントは半角数字を持たないので全角で書く（NFKC で半角に揃う）
z = lambda n: ''.join(Z[int(d)] for d in str(n))

def make(name, pages):
    c = canvas.Canvas(os.path.join(here, name))
    for title in pages:
        c.setFont('JP', 20)
        if title:
            c.drawString(50, 780, title)
        c.setFont('JP', 11)
        c.drawString(50, 700, '本文テキスト')
        c.showPage()
    c.save()

# P1: 問題×5（各2ページ）→ 解答×5（各2ページ）= 20ページ
p1 = []
for k in ['問題', '解答']:
    for r in range(1, 6):
        p1 += [f'第{z(r)}回 {k}', None]
make('workbook_p1.pdf', p1)
# P2: 交互 問1,答1,...（各1ページ）= 6ページ
make('workbook_p2.pdf', [f'第{z((i//2)+1)}回 {"問題" if i % 2 == 0 else "解答"}' for i in range(6)])
# 見出しなし 5ページ
make('plain.pdf', [None] * 5)

# 見開き（B4横 = 2×B5）: 表紙(B5縦) + 見開き3枚。左右に別の回・種別
def make_spread(name):
    c = canvas.Canvas(os.path.join(here, name))
    W, H = 1031.8, 728.5
    c.setPageSize((W / 2, H)); c.setFont('JP', 20); c.drawString(50, 650, '表紙'); c.showPage()
    heads = [('第１回 問題', '第１回 問題'), ('第２回 問題', '第２回 問題'), ('第１回 解答', '第２回 解答')]
    for l, r in heads:
        c.setPageSize((W, H)); c.setFont('JP', 20)
        c.drawString(50, 650, l); c.drawString(W / 2 + 50, 650, r)
        c.setFont('JP', 11); c.drawString(50, 600, '本文テキスト'); c.drawString(W / 2 + 50, 600, '本文テキスト')
        c.showPage()
    c.save()
make_spread('spread_b4.pdf')
