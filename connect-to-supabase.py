#!/usr/bin/env python3
"""
Wire Cupid's Society index.html to Supabase.

Run it again after any future revision of index.html — it only rewrites the
handful of blocks it knows about, and it refuses to run twice on the same file.

    python3 connect-to-supabase.py index.html -o index.supabase.html

What it changes, and nothing else:
  1. Adds the Supabase client + config above the app script
  2. PRODS is loaded from the database instead of hardcoded
  3. The homepage 4-up grid comes from the "featured" flag
  4. Product photos come from Supabase Storage (falls back to the
     inlined base64 image if a piece has no photo uploaded yet)
  5. Sold-out sizes are struck through and unselectable
  6. A piece with every size at zero gets a SOLD OUT badge
  7. Both WhatsApp buttons log a pending order before opening WhatsApp

The editorial/lookbook imagery in the static markup is left alone.
"""

import re, sys, argparse

# --------------------------------------------------------------------------
# 1. Supabase client + the loader, injected above the app script
# --------------------------------------------------------------------------
INJECT = r"""<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
// ═══════════════════════════════════════════════
// SUPABASE — live catalogue + order logging
// Paste these from Supabase → Project Settings → API.
// The anon key is safe in public: row level security lets shoppers read
// active pieces and create a pending order, and nothing else.
// ═══════════════════════════════════════════════
const SB_URL = 'https://YOUR-PROJECT.supabase.co';
const SB_KEY = 'YOUR-ANON-KEY';
const SB = window.supabase.createClient(SB_URL, SB_KEY);

// Turns database rows into the exact shape the rest of the site already
// expects, so nothing downstream had to be rewritten.
async function loadProducts(){
  const { data, error } = await SB
    .from('products')
    .select('slug,name,tag,cat,sub,color,price_ttd,price_usd,description,details,care,featured,sort_order, variants(id,size,stock), product_images(url,is_primary,sort_order)')
    .eq('status','active')
    .order('sort_order');

  if (error || !data){
    console.error('Catalogue unavailable:', error);
    return false;
  }

  PRODS = data.map(function(p){
    const sizes = (p.variants||[]).slice().sort(function(a,b){
      const order = ['XS','S','M','L','XL','XXL','One size'];
      const i = s => { const k = order.indexOf(s); return k < 0 ? 99 : k; };
      return i(a.size) - i(b.size);
    });
    const photo = (p.product_images||[]).slice().sort(function(a,b){
      return (b.is_primary - a.is_primary) || (a.sort_order - b.sort_order);
    })[0];

    return {
      id: p.slug, name: p.name, cat: p.cat, sub: p.sub, tag: p.tag || '',
      ttd: Number(p.price_ttd), usd: Number(p.price_usd), color: p.color || '',
      desc: p.description || '', details: p.details || '', care: p.care || '',
      featured: p.featured,
      sizes: sizes.map(function(v){ return v.size; }),
      stock: sizes.reduce(function(m,v){ m[v.size] = v.stock; return m; }, {}),
      variantIds: sizes.reduce(function(m,v){ m[v.size] = v.id; return m; }, {}),
      inStock: sizes.some(function(v){ return v.stock > 0; }),
      imgUrl: photo ? photo.url : '',
      img: LEGACY_IMG[p.slug] || ''
    };
  });
  return true;
}

// If a piece has no photo uploaded yet, fall back to the image already
// baked into this file so the grid never shows an empty box.
const LEGACY_IMG = {
  'crystal-night-mini':'RHINE', 'blush-bandage':'BANDAGE',
  'white-ruched-mini':'WHITE',  'black-cat-unitard':'JUMP',
  'stripe-paradise':'STRIPE',   'pink-horizon':'DUSK',
  'thrifted-slip':'WHITE'
};

function prodImg(p){
  if (p.imgUrl) return p.imgUrl;
  return IMG[p.img] ? 'data:image/jpeg;base64,' + IMG[p.img] : '';
}

function sizeStock(p, size){
  return (p.stock && typeof p.stock[size] === 'number') ? p.stock[size] : 1;
}

// ── ORDER LOGGING ──
// Every checkout writes a pending order before WhatsApp opens. She confirms
// the ones that actually paid, in the back office. If Supabase is slow or
// down, WhatsApp still opens — a shopper is never blocked by our logging.
async function logOrder(source, lines){
  try {
    const subtotal = lines.reduce(function(s,l){ return s + l.unit_price * l.qty; }, 0);
    const res = await SB.from('orders').insert({
      source: source, status: 'pending', currency: currency, subtotal: subtotal
    }).select('id,ref').single();
    if (res.error || !res.data) return null;

    await SB.from('order_items').insert(lines.map(function(l){
      return {
        order_id: res.data.id, product_id: null, variant_id: l.variant_id,
        product_name: l.product_name, size: l.size,
        unit_price: l.unit_price, qty: l.qty
      };
    }));
    return res.data.ref;
  } catch (e){
    console.warn('Order not logged:', e);
    return null;
  }
}
</script>

"""

# --------------------------------------------------------------------------
# 2. The replacements
# --------------------------------------------------------------------------

NEW_PRODS = """// ── PRODUCTS DATA ──
// Loaded live from Supabase by loadProducts(). The back office is the
// only place a piece gets added, priced, or taken down.
let PRODS = [];
"""

NEW_FEATURED = """  PRODS.filter(function(p){ return p.featured; }).slice(0,4)
       .forEach(function(p){ grid.appendChild(buildCard(p)); });"""

NEW_SIZE_PILLS = """  p.sizes.forEach(function(s){
    const btn = document.createElement('button');
    const left = sizeStock(p, s);
    btn.className = 'sz-pill' + (left === 0 ? ' out' : '');
    btn.textContent = s;
    if (left === 0){
      btn.disabled = true;
      btn.title = 'Sold out';
    } else {
      btn.onclick = function(){ selectSize(btn, s); };
    }
    szDiv.appendChild(btn);
  });"""

NEW_QUICKADD = """function quickAddCart(id){
  const p = getProd(id);
  const available = p.sizes.filter(function(s){ return sizeStock(p, s) > 0; });
  if (!available.length){ showToast(p.name + ' is sold out'); return; }
  // Middle of what's actually left, not the middle of the size run.
  addToCart(id, available[Math.floor(available.length / 2)], 1);
}"""

NEW_WABTN = """function updateWaBtn(){
  if (!curProd) return;
  document.getElementById('pd-wa').onclick = async function(){
    const line = {
      variant_id: curProd.variantIds ? curProd.variantIds[selectedSize] : null,
      product_name: curProd.name, size: selectedSize || null,
      unit_price: currency === 'TTD' ? curProd.ttd : curProd.usd, qty: pdQty
    };
    const ref = await logOrder('product_page', [line]);
    const msg = encodeURIComponent(
      "Hi! I'd like to order: " + curProd.name +
      "\\nSize: " + (selectedSize || '(please select size)') +
      "\\nColor: " + curProd.color +
      "\\nQty: " + pdQty +
      (ref ? "\\nRef: " + ref : "") +
      "\\n\\nPlease confirm availability and total."
    );
    window.open('https://wa.me/' + WA_NUM + '?text=' + msg, '_blank');
  };
}"""

NEW_CHECKOUT = """async function checkoutWA(){
  if (cart.length === 0) return;

  const lines = cart.map(function(item){
    const p = getProd(item.id);
    return {
      variant_id: p.variantIds ? p.variantIds[item.size] : null,
      product_name: p.name, size: item.size,
      unit_price: currency === 'TTD' ? p.ttd : p.usd, qty: item.qty
    };
  });
  const ref = await logOrder('cart_checkout', lines);

  let msg = "Hi! I'd like to place an order:\\n\\n";
  cart.forEach(function(item){
    const p = getProd(item.id);
    const unitPrice = currency === 'TTD' ? p.ttd : p.usd;
    msg += "• " + p.name + " (Size: " + item.size + ") x" + item.qty + " — " +
           (currency === 'TTD' ? 'TTD $' : 'USD $') + (unitPrice * item.qty) + "\\n";
  });
  msg += "\\nEstimated Total: " + (currency === 'TTD' ? 'TTD $' : 'USD $') + cartTotal();
  if (ref) msg += "\\nRef: " + ref;
  msg += "\\n\\nPlease confirm availability and total with shipping.";
  window.open('https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(msg), '_blank');
}"""

NEW_INIT = """document.addEventListener('DOMContentLoaded', async function(){
  document.body.classList.add('ready');
  imgs();
  sizeHeader();

  const ok = await loadProducts();
  if (!ok){
    showToast("Couldn't load the collection. Please refresh.");
  }
  renderHomeGrid();
  renderShopGrid();
  if (curPage === 'shop') filterShopGrid();

  updateCartBadge();
  revealInit();"""

SOLD_OUT_CSS = """
/* SOLD OUT — a size that's gone stays visible but can't be picked */
.sz-pill.out{opacity:.4;cursor:not-allowed;text-decoration:line-through}
.sz-pill.out:hover{border-color:var(--border)}
.pbadge.sold{background:var(--fg);color:#fff}
.pcard.sold .pc-img img{opacity:.62}
"""

REPLACEMENTS = [
    ("products array",
     re.compile(r"// ── PRODUCTS DATA ──\nconst PRODS = \[.*?\n\];\n", re.S),
     NEW_PRODS),

    ("homepage featured grid",
     re.compile(r"  const featured = \['crystal-night-mini'.*?\n  featured\.forEach\([^\n]*\n", re.S),
     NEW_FEATURED + "\n"),

    ("card image source",
     re.compile(r"const imgSrc = IMG\[p\.img\] \? 'data:image/jpeg;base64,'\+IMG\[p\.img\] : '';"),
     "const imgSrc = prodImg(p);"),

    ("product page image",
     re.compile(r"  if \(IMG\[p\.img\]\) imgEl\.src = 'data:image/jpeg;base64,' \+ IMG\[p\.img\];"),
     "  imgEl.src = prodImg(p);"),

    ("sold out badge",
     re.compile(r"const badgeClass = \(p\.tag === 'New In' \|\| p\.tag === 'Bestseller'\) \? 'pk' : '';"),
     "const badgeClass = p.inStock === false ? 'sold'\n"
     "    : (p.tag === 'New In' || p.tag === 'Bestseller') ? 'pk' : '';\n"
     "  const badgeText = p.inStock === false ? 'Sold Out' : p.tag;\n"
     "  if (p.inStock === false) card.classList.add('sold');"),

    ("badge text",
     re.compile(r"'<span class=\"pbadge '\+badgeClass\+'\">'\+p\.tag\+'</span>' \+"),
     "'<span class=\"pbadge '+badgeClass+'\">'+badgeText+'</span>' +"),

    ("size pills",
     re.compile(r"  p\.sizes\.forEach\(function\(s\)\{\n    const btn = document\.createElement\('button'\);\n    btn\.className = 'sz-pill';.*?\n  \}\);", re.S),
     NEW_SIZE_PILLS),

    ("quick add to cart",
     re.compile(r"function quickAddCart\(id\)\{.*?\n\}", re.S),
     NEW_QUICKADD),

    ("product page WhatsApp button",
     re.compile(r"function updateWaBtn\(\)\{.*?\n\}\n", re.S),
     NEW_WABTN + "\n"),

    ("cart checkout",
     re.compile(r"function checkoutWA\(\)\{.*?\n\}\n", re.S),
     NEW_CHECKOUT + "\n"),

    ("startup",
     re.compile(r"document\.addEventListener\('DOMContentLoaded', function\(\)\{\n  document\.body\.classList\.add\('ready'\);\n  imgs\(\);\n  sizeHeader\(\);\n  renderHomeGrid\(\);\n  renderShopGrid\(\);\n  updateCartBadge\(\);\n  revealInit\(\);"),
     NEW_INIT),
]


def patch(src: str) -> str:
    if 'SB_URL' in src:
        sys.exit("This file is already connected to Supabase. Patch the "
                 "original index.html instead.")

    for label, pattern, replacement in REPLACEMENTS:
        src, n = pattern.subn(lambda m: replacement, src, count=0)
        if n == 0:
            sys.exit(f"Couldn't find the '{label}' block. index.html has changed "
                     f"shape — update the pattern for that block in this script.")
        print(f"  patched  {label}  ({n}×)")

    # sold-out styles, appended to the existing stylesheet
    src, n = re.subn(r"\n</style>", SOLD_OUT_CSS + "</style>", src, count=1)
    if n == 0:
        sys.exit("Couldn't find the closing </style> tag.")
    print("  patched  sold-out styles")

    # the client + loader, immediately above the app script
    marker = "<script>\n// ═══════════════════════════════════════════════\n// CUPID'S SOCIETY — Core App Logic"
    if marker not in src:
        sys.exit("Couldn't find the app script to inject above.")
    src = src.replace(marker, INJECT + marker, 1)
    print("  patched  Supabase client")

    return src


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('source', nargs='?', default='index.html')
    ap.add_argument('-o', '--out', default='index.supabase.html')
    a = ap.parse_args()

    original = open(a.source, encoding='utf-8').read()
    print(f"Patching {a.source} …")
    open(a.out, 'w', encoding='utf-8').write(patch(original))
    print(f"\nWrote {a.out}")
    print("Now paste SB_URL and SB_KEY near the top of the new file.")
