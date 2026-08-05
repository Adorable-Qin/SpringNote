import io

path = 'lib/features/home/home_page.dart'
with io.open(path, 'r', encoding='utf-8', newline='') as f:
    lines = f.readlines()

# 定位包含“更多功能”的 Padding 块（以行号为准，内容做断言）
idx = next(i for i, line in enumerate(lines) if '更多功能' in line)
start = idx - 2  # Padding( 行
end = idx + 7    # ), 行（含）
block = lines[start:end + 1]
assert block[0].lstrip().startswith('Padding('), block[0]
assert block[-1].rstrip().endswith('),'), block[-1]
del lines[start:end + 1]

with io.open(path, 'w', encoding='utf-8', newline='') as f:
    f.writelines(lines)
print('removed lines', start + 1, 'to', end + 1)
