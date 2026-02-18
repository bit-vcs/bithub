import { test, expect } from '@playwright/test';

type ContrastTarget = {
  label: string;
  selector: string;
  minRatio: number;
  allMatches?: boolean;
};

type ContrastResult = {
  label: string;
  minRatio: number;
  ratio: number;
  sampled: number;
};

const WCAG_AA_NORMAL_TEXT = 4.5;

const CONTRAST_TARGETS: ContrastTarget[] = [
  { label: 'body text', selector: 'body', minRatio: WCAG_AA_NORMAL_TEXT },
  { label: 'header text', selector: 'header', minRatio: WCAG_AA_NORMAL_TEXT },
  {
    label: 'sidebar link',
    selector: 'nav[aria-label="repository files"] a',
    minRatio: WCAG_AA_NORMAL_TEXT,
  },
  { label: 'main prose', selector: 'main section', minRatio: WCAG_AA_NORMAL_TEXT },
  { label: 'inline code', selector: 'main code', minRatio: WCAG_AA_NORMAL_TEXT },
  {
    label: 'highlighted token',
    selector: 'main pre.highlight code span[style*="color:"]',
    minRatio: WCAG_AA_NORMAL_TEXT,
    allMatches: true,
  },
];

async function collectContrastResults(
  page: Parameters<typeof test>[0]['page'],
  targets: ContrastTarget[],
): Promise<ContrastResult[]> {
  return page.evaluate((rawTargets) => {
    const parseColor = (value: string): [number, number, number, number] | null => {
      const raw = value.trim();
      if (raw === 'transparent') return [0, 0, 0, 0];
      const match = raw.match(/^rgba?\(([^)]+)\)$/i);
      if (!match) return null;
      const parts = match[1].split(',').map((part) => part.trim());
      if (parts.length < 3) return null;
      const r = Number(parts[0]);
      const g = Number(parts[1]);
      const b = Number(parts[2]);
      const a = parts.length >= 4 ? Number(parts[3]) : 1;
      if ([r, g, b, a].some((n) => Number.isNaN(n))) return null;
      return [r, g, b, a];
    };

    const toLinear = (channel: number): number => {
      const srgb = channel / 255;
      if (srgb <= 0.03928) return srgb / 12.92;
      return ((srgb + 0.055) / 1.055) ** 2.4;
    };

    const luminance = (rgb: [number, number, number]): number => (
      0.2126 * toLinear(rgb[0]) + 0.7152 * toLinear(rgb[1]) + 0.0722 * toLinear(rgb[2])
    );

    const contrastRatio = (
      fg: [number, number, number],
      bg: [number, number, number],
    ): number => {
      const l1 = luminance(fg);
      const l2 = luminance(bg);
      const light = Math.max(l1, l2);
      const dark = Math.min(l1, l2);
      return (light + 0.05) / (dark + 0.05);
    };

    const blend = (
      fg: [number, number, number, number],
      bg: [number, number, number, number],
    ): [number, number, number] => {
      const alpha = fg[3];
      return [
        fg[0] * alpha + bg[0] * (1 - alpha),
        fg[1] * alpha + bg[1] * (1 - alpha),
        fg[2] * alpha + bg[2] * (1 - alpha),
      ];
    };

    const resolveBackground = (element: Element): [number, number, number, number] => {
      let current: Element | null = element;
      while (current) {
        const bg = parseColor(getComputedStyle(current).backgroundColor);
        if (bg && bg[3] > 0) return bg;
        current = current.parentElement;
      }
      return parseColor(getComputedStyle(document.body).backgroundColor) ?? [255, 255, 255, 1];
    };

    const ratioForElement = (element: Element): number => {
      const fg = parseColor(getComputedStyle(element).color) ?? [0, 0, 0, 1];
      const bg = resolveBackground(element);
      const effectiveFg: [number, number, number] = fg[3] < 1
        ? blend(fg, bg)
        : [fg[0], fg[1], fg[2]];
      const effectiveBg: [number, number, number] = [bg[0], bg[1], bg[2]];
      return contrastRatio(effectiveFg, effectiveBg);
    };

    return rawTargets.map((target) => {
      const nodes = Array.from(document.querySelectorAll(target.selector));
      if (nodes.length === 0) {
        return {
          label: target.label,
          minRatio: target.minRatio,
          ratio: 0,
          sampled: 0,
        };
      }
      const sampledNodes = target.allMatches ? nodes : [nodes[0]];
      let min = Number.POSITIVE_INFINITY;
      for (const node of sampledNodes) {
        min = Math.min(min, ratioForElement(node));
      }
      return {
        label: target.label,
        minRatio: target.minRatio,
        ratio: min,
        sampled: sampledNodes.length,
      };
    });
  }, targets);
}

async function expectAccessibleTextContrast(
  page: Parameters<typeof test>[0]['page'],
  scheme: 'light' | 'dark',
) {
  await page.emulateMedia({ colorScheme: scheme });
  await page.goto('/blob/src/cmd/bithub/main.mbt');

  const results = await collectContrastResults(page, CONTRAST_TARGETS);
  for (const result of results) {
    expect(
      result.sampled,
      `${scheme}: selector "${result.label}" の要素が見つかりません`,
    ).toBeGreaterThan(0);
    expect(
      result.ratio,
      `${scheme}: "${result.label}" のコントラスト比 ${result.ratio.toFixed(2)} が閾値 ${result.minRatio} 未満です`,
    ).toBeGreaterThanOrEqual(result.minRatio);
  }
}

async function setTreeDirExpanded(
  page: Parameters<typeof test>[0]['page'],
  dirPath: string,
  expanded: boolean,
) {
  const dir = page.locator(`nav[aria-label="repository files"] details[data-tree-path="${dirPath}"]`);
  await expect(dir).toBeVisible();

  const before = await dir.evaluate((el) => (el as HTMLDetailsElement).open);
  if (before !== expanded) {
    await dir.locator('summary').first().click();
  }

  await expect
    .poll(async () => dir.evaluate((el) => (el as HTMLDetailsElement).open))
    .toBe(expanded);
}

test('accessibility contrast passes in light mode', async ({ page }) => {
  await expectAccessibleTextContrast(page, 'light');
});

test('accessibility contrast passes in dark mode', async ({ page }) => {
  await expectAccessibleTextContrast(page, 'dark');
});

test('root opens README.md by default', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('link', { name: /\[\*\] README\.md/ })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'bithub' })).toBeVisible();
  await expect(page.locator('main')).toContainText('README.md');
  await expect(page.locator('main')).toContainText('Current Direction');
});

test('header is fixed to top', async ({ page }) => {
  await page.goto('/');

  const banner = page.getByRole('banner');
  await expect(banner).toBeVisible();

  const style = await banner.evaluate((el) => {
    const s = getComputedStyle(el);
    return { position: s.position, top: s.top };
  });
  expect(style.position).toBe('fixed');
  expect(style.top).toBe('0px');
});

test('header root path replaces HOME prefix with tilde', async ({ page }) => {
  const home = process.env.HOME ?? '';
  test.skip(
    home.length === 0 || !(process.cwd() === home || process.cwd().startsWith(`${home}/`)),
    'HOME prefix check is unavailable in this environment',
  );

  await page.goto('/');
  const headerText = await page.getByRole('banner').innerText();
  expect(headerText).toContain('~');
  expect(headerText).not.toContain(home);
});

test('dark mode applies dark color palette', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/');

  const palette = await page.evaluate(() => {
    const body = getComputedStyle(document.body);
    const header = getComputedStyle(document.querySelector('header')!);
    return {
      bodyBackground: body.backgroundColor,
      bodyText: body.color,
      headerBackground: header.backgroundColor,
    };
  });

  expect(palette.bodyBackground).toBe('rgb(11, 18, 32)');
  expect(palette.bodyText).toBe('rgb(219, 231, 255)');
  expect(palette.headerBackground).toBe('rgb(17, 26, 46)');
});

test('root uses split layout for file list and preview', async ({ page }) => {
  await page.goto('/');

  const splitLayout = page.locator('.split-layout');
  await expect(splitLayout).toBeVisible();
  const sidebar = splitLayout.locator('.file-sidebar');
  await expect(sidebar).toBeVisible();
  const repoNav = page.getByRole('navigation', { name: 'repository files' });
  await expect(repoNav).toBeVisible();
  await expect(splitLayout.locator('main')).toBeVisible();

  const columnCount = await splitLayout.evaluate((el) => {
    const template = getComputedStyle(el).gridTemplateColumns.trim();
    return template.length === 0 ? 0 : template.split(/\s+/).length;
  });
  expect(columnCount).toBeGreaterThanOrEqual(2);

  const sidebarOverflowY = await sidebar.evaluate((el) => getComputedStyle(el).overflowY);
  expect(sidebarOverflowY).toBe('auto');

  const breadcrumbOverflowY = await page
    .getByRole('navigation', { name: 'Breadcrumb' })
    .evaluate((el) => getComputedStyle(el).overflowY);
  expect(breadcrumbOverflowY).not.toBe('auto');

  const heights = await splitLayout.evaluate((el) => {
    const sidebar = el.querySelector('.file-sidebar');
    return {
      layoutHeight: el.clientHeight,
      sidebarHeight: sidebar ? sidebar.clientHeight : 0,
    };
  });
  expect(heights.layoutHeight).toBeGreaterThan(0);
  expect(heights.sidebarHeight).toBeGreaterThanOrEqual(heights.layoutHeight - 2);

  const scrollState = await splitLayout.evaluate((el) => {
    const main = el.querySelector('main');
    const sidebar = el.querySelector('.file-sidebar');
    if (!(main instanceof HTMLElement) || !(sidebar instanceof HTMLElement)) {
      return null;
    }
    main.scrollTop = 240;
    const mainAfter = main.scrollTop;
    const sidebarAfterMain = sidebar.scrollTop;
    const sidebarCanScroll = sidebar.scrollHeight > sidebar.clientHeight;
    sidebar.scrollTop = sidebarCanScroll ? 180 : 0;
    return {
      mainAfter,
      sidebarAfterMain,
      sidebarCanScroll,
      sidebarAfter: sidebar.scrollTop,
      mainAfterSidebar: main.scrollTop,
      pageScrollable: document.documentElement.scrollHeight > document.documentElement.clientHeight,
    };
  });
  expect(scrollState).not.toBeNull();
  expect(scrollState!.mainAfter).toBeGreaterThan(0);
  expect(scrollState!.sidebarAfterMain).toBe(0);
  if (scrollState!.sidebarCanScroll) {
    expect(scrollState!.sidebarAfter).toBeGreaterThan(0);
  } else {
    expect(scrollState!.sidebarAfter).toBe(0);
  }
  expect(scrollState!.mainAfterSidebar).toBe(scrollState!.mainAfter);
  expect(scrollState!.pageScrollable).toBeFalsy();
});

test('mobile layout switches to stacked preview-first layout', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');

  const splitLayout = page.locator('.split-layout');
  await expect(splitLayout).toBeVisible();
  const sidebar = splitLayout.locator('.file-sidebar');
  await expect(sidebar).toBeVisible();

  const nav = page.getByRole('navigation', { name: 'repository files' });
  await expect(nav).toBeVisible();

  const navPosition = await nav.evaluate((el) => getComputedStyle(el).position);
  expect(navPosition).toBe('static');

  const mainOrder = await splitLayout.locator('main').evaluate((el) => getComputedStyle(el).order);
  const sidebarOrder = await sidebar.evaluate((el) => getComputedStyle(el).order);
  expect(Number(mainOrder)).toBeLessThan(Number(sidebarOrder));
});

test('can open a source file from nav', async ({ page }) => {
  await page.goto('/');

  await setTreeDirExpanded(page, 'src', true);
  await setTreeDirExpanded(page, 'src/cmd', true);
  await setTreeDirExpanded(page, 'src/cmd/bithub', true);

  await page
    .locator('nav[aria-label="repository files"] details[data-tree-path="src/cmd/bithub"]')
    .getByRole('link', { name: 'main.mbt' })
    .click();

  await expect(page).toHaveURL(/\/blob\/src\/cmd\/bithub\/main\.mbt$/);
  await expect(page.locator('main')).toContainText('fn main');
});

test('file tree can expand and collapse directories', async ({ page }) => {
  await page.goto('/');

  await setTreeDirExpanded(page, 'src', true);
  await setTreeDirExpanded(page, 'src', false);
});

test('file tree hides list bullets', async ({ page }) => {
  await page.goto('/');

  const style = await page
    .locator('nav[aria-label="repository files"] ul[role="tree"]')
    .evaluate((el) => {
      const ulStyle = getComputedStyle(el);
      const firstLi = el.querySelector('li[role="treeitem"]');
      const liStyle = firstLi ? getComputedStyle(firstLi) : null;
      return {
        ulListStyle: ulStyle.listStyleType,
        liListStyle: liStyle?.listStyleType ?? '',
      };
    });

  expect(style.ulListStyle).toBe('none');
  expect(style.liListStyle).toBe('none');
});

test('file tree shows directory and file icons', async ({ page }) => {
  await page.goto('/');

  await expect(
    page.locator('details[data-tree-path="src"] > summary .file-tree-icon-dir').first(),
  ).toBeVisible();
  await setTreeDirExpanded(page, 'src', true);
  await setTreeDirExpanded(page, 'src/cmd', true);
  await setTreeDirExpanded(page, 'src/cmd/main', true);
  await expect(
    page.locator('details[data-tree-path="src/cmd/main"] .file-tree-icon-file').first(),
  ).toBeVisible();
});

test('file tree nested directories are clearly indented', async ({ page }) => {
  await page.goto('/');

  await setTreeDirExpanded(page, 'src', true);
  await setTreeDirExpanded(page, 'src/cmd', true);
  await setTreeDirExpanded(page, 'src/cmd/main', true);

  const positions = await page.evaluate(() => {
    const left = (selector: string) => {
      const el = document.querySelector(selector);
      if (!(el instanceof HTMLElement)) return -1;
      return el.getBoundingClientRect().left;
    };
    const root = left('details[data-tree-path="src"] > summary .file-tree-label');
    const lvl1 = left('details[data-tree-path="src/cmd"] > summary .file-tree-label');
    const lvl2 = left('details[data-tree-path="src/cmd/main"] > summary .file-tree-label');
    const file = left('a[data-tree-path="src/cmd/main/main.mbt"] .file-tree-label');
    return { root, lvl1, lvl2, file };
  });

  expect(positions.root).toBeGreaterThanOrEqual(0);
  expect(positions.lvl1 - positions.root).toBeGreaterThanOrEqual(7);
  expect(positions.lvl1 - positions.root).toBeLessThanOrEqual(11);
  expect(positions.lvl2 - positions.lvl1).toBeGreaterThanOrEqual(7);
  expect(positions.lvl2 - positions.lvl1).toBeLessThanOrEqual(11);
  expect(positions.file - positions.lvl2).toBeGreaterThanOrEqual(8);
  expect(positions.file - positions.lvl2).toBeLessThanOrEqual(12);
});

test('file tree supports keyboard navigation for expand and collapse', async ({ page }) => {
  await page.goto('/');

  const srcDir = page.locator('details[data-tree-path="src"]');
  const srcSummary = page.locator('details[data-tree-path="src"] > summary');
  await srcSummary.focus();

  await page.keyboard.press('ArrowRight');
  await expect
    .poll(async () => srcDir.evaluate((el) => (el as HTMLDetailsElement).open))
    .toBe(true);

  await page.keyboard.press('ArrowRight');
  await expect
    .poll(
      async () =>
        page.evaluate(
          () => (document.activeElement as HTMLElement | null)?.getAttribute('data-tree-path') ?? '',
        ),
      { message: 'ArrowRight on expanded dir should move focus to first child' },
    )
    .not.toBe('src');

  await page.keyboard.press('ArrowLeft');
  await expect(srcSummary).toBeFocused();

  await page.keyboard.press('ArrowLeft');
  await expect
    .poll(async () => srcDir.evaluate((el) => (el as HTMLDetailsElement).open))
    .toBe(false);
});

test('split boundary can be dragged to resize filer width', async ({ page }) => {
  await page.goto('/');

  const splitLayout = page.locator('.split-layout');
  const resizer = splitLayout.locator('.split-resizer');
  await expect(resizer).toBeVisible();

  const before = await splitLayout.evaluate((el) => {
    const cols = getComputedStyle(el).gridTemplateColumns.trim().split(/\s+/);
    const first = Number.parseFloat(cols[0] ?? '0');
    return Number.isFinite(first) ? first : 0;
  });

  const box = await resizer.boundingBox();
  expect(box).not.toBeNull();
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2);
  await page.mouse.down();
  await page.mouse.move(box!.x + box!.width / 2 + 96, box!.y + box!.height / 2);
  await page.mouse.up();

  const after = await splitLayout.evaluate((el) => {
    const cols = getComputedStyle(el).gridTemplateColumns.trim().split(/\s+/);
    const first = Number.parseFloat(cols[0] ?? '0');
    return Number.isFinite(first) ? first : 0;
  });

  expect(after).toBeGreaterThan(before + 40);
});

test('code preview uses syntree highlight html', async ({ page }) => {
  await page.goto('/blob/src/cmd/bithub/main.mbt');

  await expect(page.locator('main pre.highlight')).toBeVisible();
  const coloredSpanCount = await page.locator('main pre.highlight code span[style*="color:"]').count();
  expect(coloredSpanCount).toBeGreaterThan(0);
});

test('path traversal is rejected', async ({ page }) => {
  const response = await page.goto('/blob/..%2FREADME.md');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(400);
  await expect(page.locator('main')).toContainText('Invalid path.');
});

test('issues list page is available', async ({ page }) => {
  await page.goto('/');

  await page.getByRole('link', { name: 'issues' }).click();

  await expect(page).toHaveURL(/\/issues$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Issues' })).toBeVisible();
});

test('issues route works with query string', async ({ page }) => {
  await page.goto('/issues?state=open');

  await expect(page.getByRole('heading', { level: 1, name: 'Issues' })).toBeVisible();
});

test('blob route works with query string', async ({ page }) => {
  const response = await page.goto('/blob/README.md?raw=1');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(200);
  await expect(page.locator('main')).toContainText('README.md');
});

test('missing blob returns 404 page', async ({ page }) => {
  const response = await page.goto('/blob/not-found-file.txt');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(404);
  await expect(page.locator('main')).toContainText('File not found');
});

test('unknown route returns 404 page', async ({ page }) => {
  const response = await page.goto('/__no_such_route__');

  expect(response).not.toBeNull();
  expect(response!.status()).toBe(404);
  await expect(page.locator('main')).toContainText('Route not found.');
});

test('can navigate back to home from issues page', async ({ page }) => {
  await page.goto('/issues');
  await page.getByRole('banner').getByRole('link', { name: 'bithub' }).click();

  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('main')).toContainText('README.md');
});
