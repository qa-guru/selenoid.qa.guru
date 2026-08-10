# Release pin — UI v3.0.24 (hub v3.0.8 + cm v3.0.2)

**Дата:** 10 августа 2026  
**Stack pins:** hub **v3.0.8** · UI **v3.0.24** · cm **v3.0.2**

- SessionArchive: semantic sortable table, default newest finished first
- Sort/page persist in URL query string
- Actions column widened for video + log + HAR + delete
- Inactive sort-arrow contrast on dark headers

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.8 -f ui_version=v3.0.24
```
