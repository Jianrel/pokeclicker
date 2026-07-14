# pt-BR translation conventions for this fork

Used by the automated update pipeline (`automation/auto-update.ps1`) when it
invokes Claude to fill in newly-added, untranslated strings after merging
upstream changes. Follow these conventions for consistency with the existing
translated content.

## Established glossary (keep consistent)

- Team X -> Equipe X (e.g. Team Rocket -> Equipe Rocket, matches the anime dub)
- Gym / Gym Leader -> Ginásio / Líder de Ginásio
- Route N -> Rota N
- Dungeon / Clear a dungeon -> Masmorra / Complete a masmorra
- Battle Frontier -> Fronteira de Batalha
- Hatchery -> Encubadora (kept as the existing, slightly non-standard spelling
  already used across the project's translations, for consistency)
- Hatch (an egg) -> Choque (verb "chocar")
- Berry -> Fruta, Mulch -> Fertilizante
- Address the player informally as "você"

## What to translate vs. leave in English

- **Pokémon species/form names** (plain keys like "Bulbasaur", "Mr. Mime",
  "Tapu Koko", "Mega Venusaur") are **not translated** — Brazilian
  Portuguese Pokémon games use the same species names as English. If a new
  species/form appears with the value identical to the English key, that's
  correct; leave it as-is.
- **City/Town/Route/Region/dungeon proper names** (Pallet Town, Viridian
  City, Sky Pillar, etc.) and **NPC/character names** (Giovanni, Lysandre,
  Cyrus, etc.) stay in English — there's no consistent official pt-BR
  localization for most of these across all regions, so keeping them in
  English avoids inventing inconsistent names.
- **Everything else** (quest descriptions/steps, settings labels, logbook
  messages, Pokémon category/flavor text, the `alt` variant/type names in
  pokemon.json) should be translated into natural Brazilian Portuguese.
- Keep `[[reference]]` tokens (e.g. `[[alt.mega]]`, `[[pokemon::Pikachu]]`)
  and `{{variable}}` interpolation tokens exactly as they appear — do not
  translate or remove their contents, only translate the surrounding text.

## Process

1. Read `automation/missing-translations.json` — it lists, per file, every
   key (dot-path) whose pt-BR value is currently empty, with the English
   text for reference.
2. For each entry, open the corresponding file at
   `src/translations/locales/pt-BR/<file>` and set that key's value to the
   Portuguese translation (preserving the exact key path and valid JSON).
3. Do not touch any key that isn't listed in the report.
4. Do not modify any file outside `src/translations/locales/pt-BR/`.
