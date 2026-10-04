<template>
  <svg
    v-if="icon"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    :fill="icon.fill ? 'currentColor' : 'none'"
    :stroke="icon.fill ? 'none' : 'currentColor'"
    :stroke-width="stroke"
    stroke-linecap="round"
    stroke-linejoin="round"
  >
    <path v-for="d in icon.paths || []" :key="d" :d="d" />
    <circle v-for="c in icon.circles || []" :key="`c${c.join()}`" :cx="c[0]" :cy="c[1]" :r="c[2]" />
    <rect
      v-for="r in icon.rects || []"
      :key="`r${r.join()}`"
      :x="r[0]" :y="r[1]" :width="r[2]" :height="r[3]" :rx="r[4]"
    />
    <polyline v-for="p in icon.polylines || []" :key="`p${p}`" :points="p" />
  </svg>
</template>

<script setup>
import { computed } from 'vue'

// 图标表：与设计稿 /Users/MacBook/Downloads/dac-ui-enterprise-pro 的 inline SVG 保持一致
// （viewBox 统一 0 0 24 24，线性描边、圆角端点）。设计稿未出现的图标按同一风格自绘，
// 已在下方注释标注「自绘」。star 是唯一的实心图标。
const ICONS = {
  // ── 统计 / 人员 / 文档 ──
  bar: { paths: ['M18 20V10M12 20V4M6 20v-6'] },
  users: {
    paths: ['M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2', 'M23 21v-2a4 4 0 0 0-3-3.87'],
    circles: [[9, 7, 4]],
  },
  file: {
    paths: ['M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'],
    polylines: ['14 2 14 8 20 8'],
  },

  // ── 页面内图标 ──
  user: { paths: ['M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2'], circles: [[9, 7, 4]] },
  cube: { paths: ['M12 2 2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5'] },
  donut: { paths: ['M21.2 15.9A10 10 0 1 1 8.1 2.8', 'M22 12A10 10 0 0 0 12 2v10z'] },
  star: {
    fill: true,
    paths: ['M12 2l1.8 5.6L19.5 9.4l-4.5 3.4L16.2 19 12 15.9 7.8 19l1.2-6.2L4.5 9.4l5.7-1.8z'],
  },
  check: { polylines: ['20 6 9 17 4 12'] },
  search: { paths: ['m20 20-3.5-3.5'], circles: [[11, 11, 7]] },
  clock: { paths: ['M12 7v5l3.5 2'], circles: [[12, 12, 9]] },
  refresh: { paths: ['M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67'] },

  // ── 自绘（设计稿未出现，按同一线性风格补齐）──
  link: {
    paths: [
      'M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5',
      'M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5',
    ],
  },
  scissors: {
    paths: ['M20 4 8.12 15.88', 'M14.47 14.48 20 20', 'M8.12 8.12 12 12'],
    circles: [[6, 6, 3], [6, 18, 3]],
  },
  trash: {
    paths: [
      'M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6m5 0V4a2 2 0 0 1 2-2h0a2 2 0 0 1 2 2v2',
      'M10 11v6',
      'M14 11v6',
    ],
    polylines: ['3 6 5 6 21 6'],
  },
  rocket: {
    paths: [
      'M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z',
      'M12 15l-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z',
      'M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0',
      'M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5',
    ],
  },
  bot: {
    paths: ['M12 7v4', 'M8 16h.01', 'M16 16h.01'],
    rects: [[3, 11, 18, 10, 2]],
    circles: [[12, 5, 2]],
  },
  tag: {
    paths: ['M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z', 'M7 7h.01'],
  },
  calendar: {
    paths: ['M16 2v4', 'M8 2v4', 'M3 10h18'],
    rects: [[3, 4, 18, 18, 2]],
  },
  x: { paths: ['M18 6 6 18', 'M6 6l12 12'] },
  skip: { paths: ['M5 4l10 8-10 8z', 'M19 5v14'] },
  alert: {
    paths: [
      'M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z',
      'M12 9v4',
      'M12 17h.01',
    ],
  },
}

const props = defineProps({
  name: { type: String, required: true },
  size: { type: [Number, String], default: 13 },
  stroke: { type: [Number, String], default: 2 },
})

const icon = computed(() => ICONS[props.name] || null)
</script>
