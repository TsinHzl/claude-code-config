<template>
  <div class="ep-person">
    <div class="ep-av" :style="owner.avatarStyle">{{ initials(owner.name) }}</div>
    <div style="min-width:0;flex:1">
      <div class="ep-person-name">{{ owner.name }}</div>
      <div class="ep-person-sub">{{ owner.email }}</div>
    </div>
    <span class="ep-person-role"><span class="ep-bd" :style="owner.tagStyle">{{ owner.tag }}</span></span>
  </div>
</template>

<script setup>
import { initials } from '../../utils/format'

defineProps({
  owner: { type: Object, required: true },
})
</script>
