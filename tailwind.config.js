module.exports = {
  content: [
    './_drafts/**/*.html',
    './_includes/**/*.html',
    './_layouts/**/*.html',
    './_posts/*.md',
    './*.md',
    './*.html',
  ],

  theme: {
    theme: {
      extend: {
        fontFamily: {
          sans: ['Source Code Pro', 'monospace'],
        },
        typography: {
          DEFAULT: {
            css: {
              fontFamily: 'Source Code Pro, monospace',
              // Any other global typography styles you wish to apply
            },
          },
        },

      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ]
}
