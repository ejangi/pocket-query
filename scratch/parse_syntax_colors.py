import json

with open("scratch/figma_node_15_183.json") as f:
    data = json.load(f)

node = data["nodes"]["15:183"]["document"]
chars = node["characters"]
overrides = node.get("characterStyleOverrides", [])
override_table = node.get("styleOverrideTable", {})

def color_to_hex(c):
    if not c:
        return None
    r = int(c.get('r', 0) * 255)
    g = int(c.get('g', 0) * 255)
    b = int(c.get('b', 0) * 255)
    a = c.get('a', 1.0)
    return f"#{r:02X}{g:02X}{b:02X}"

default_fill = node.get("fills", [{}])[0].get("color")
default_color_hex = color_to_hex(default_fill)

print("Default color:", default_color_hex)
print("\n--- Style Override Table ---")
for key, style in override_table.items():
    fill = style.get("fills", [{}])[0].get("color")
    font_style = style.get("fontStyle", "Regular")
    print(f"Key {key}: Color {color_to_hex(fill)}, FontStyle: {font_style}")

print("\n--- Word by Word Style Mapping ---")
i = 0
while i < len(chars):
    char = chars[i]
    style_key = str(overrides[i]) if i < len(overrides) and overrides[i] != 0 else "default"
    color = default_color_hex
    font_style = "Regular"
    if style_key in override_table:
        s = override_table[style_key]
        color = color_to_hex(s.get("fills", [{}])[0].get("color"))
        font_style = s.get("fontStyle", "Regular")
    
    j = i + 1
    word = char
    while j < len(chars):
        next_key = str(overrides[j]) if j < len(overrides) and overrides[j] != 0 else "default"
        if next_key == style_key:
            word += chars[j]
            j += 1
        else:
            break
    
    print(f"Text: '{word.replace(chr(10), '\\n')}' | StyleKey: {style_key} | Color: {color} | FontStyle: {font_style}")
    i = j
