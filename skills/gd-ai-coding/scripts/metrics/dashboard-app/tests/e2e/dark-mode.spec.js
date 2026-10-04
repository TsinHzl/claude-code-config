import { test, expect } from '@playwright/test'
import { pathToFileURL } from 'node:url'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

// dist-single/index.html 是模板，__DATA_PLACEHOLDER__ 由 scripts/metrics/gen-dashboard.sh
// 替换成真实 JSON 才是可直接打开的离线文件。这里按同样方式生成再验证。
function buildOfflineFile() {
  const tmpl = fs.readFileSync(path.resolve('dist-single/index.html'), 'utf8')
  const fixture = {
    generatedAt: '2026-08-18 20:00',
    committers: [{ committer: 'a@x.com', committer_name: '张三', requirements: [] }],
    requirements_index: [],
  }
  const out = tmpl.replace('__DATA_PLACEHOLDER__', JSON.stringify(fixture))
  const file = path.join(os.tmpdir(), 'dac-dark-mode-offline.html')
  fs.writeFileSync(file, out)
  return pathToFileURL(file).href
}

test('dist-single 以 file:// 打开不白屏，主题可切换且刷新后保持', async ({ page }) => {
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e)))

  await page.goto(buildOfflineFile())

  // 不白屏：侧栏与概览 tab 均已渲染
  await expect(page.locator('.nav-rail')).toBeVisible()
  await expect(page.locator('#tab-overview')).toHaveClass(/active/)

  // 首屏默认亮色
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
  await page.screenshot({ path: 'test-results/dark-mode-light.png' })

  // 切到暗色
  await page.locator('.nav-theme-btn').click()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor))
    .toBe('rgb(11, 15, 25)') // --bg: #0B0F19
  expect(await page.evaluate(() =>
    getComputedStyle(document.querySelector('.nav-brand-title')).color
  )).toBe('rgb(248, 250, 252)') // --nav-title 暗色下不跟随 --sub-bg 变深
  await page.screenshot({ path: 'test-results/dark-mode-dark.png' })

  // 刷新后保持暗色
  await page.reload()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')

  // 切回亮色
  await page.locator('.nav-theme-btn').click()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')

  expect(errors).toEqual([])
})
