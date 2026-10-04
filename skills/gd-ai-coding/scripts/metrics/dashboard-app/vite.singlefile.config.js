import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  plugins: [vue(), viteSingleFile()],
  build: {
    outDir: 'dist-single',
    rollupOptions: {
      input: fileURLToPath(new URL('./offline.html', import.meta.url)),
    },
  },
})
