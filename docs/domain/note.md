# Ubiquitous language: Note

The sample bounded context lives in `Lib`; Redis persistence lives in
`App/Adapters/Redis`.

| Term              | Meaning                                                   |
| ----------------- | --------------------------------------------------------- |
| `NoteRecord`      | Immutable title and body without identity.                |
| `NotePrincipal`   | A persisted note identity paired with its record.         |
| `INoteSummariser` | Produces the single-line note preview.                    |
| `NoteSummariser`  | Pure implementation of the preview rules.                 |
| `INoteRepository` | Domain-owned persistence boundary with `Save` and `Find`. |

Use “note”, “record”, “principal”, “preview”, `Save`, and `Find` consistently.
Avoid memo/item/entity synonyms or infrastructure language in the domain layer.
