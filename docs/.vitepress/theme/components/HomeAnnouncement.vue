<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const { lang } = useData()

const isZh = computed(() => lang.value.startsWith('zh'))

const announcement = computed(() => {
  if (isZh.value) {
    return {
      href: 'https://github.com/Adorable-Qin/SpringNote-Agenda/releases/latest',
      prefix: 'SpringNote-Agenda',
      text: '查看最新版本与更新说明'
    }
  }

  return {
    href: 'https://github.com/Adorable-Qin/SpringNote-Agenda/releases/latest',
    prefix: 'SpringNote-Agenda',
    text: 'View the latest release and update notes'
  }
})
</script>

<template>
  <a class="home-announcement" :href="announcement.href">
    <strong>{{ announcement.prefix }}:</strong>
    <span>{{ announcement.text }}</span>
    <span aria-hidden="true">-&gt;</span>
  </a>
</template>