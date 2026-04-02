# Spec — Projet `reverse_proxy`

## Contexte

Le projet `reverse_proxy` est un composant d'infrastructure du VPS personnel.
Il expose des projets web internes via un reverse proxy Caddy, routé par path HTTP.
Il est piloté manuellement ou via claude-bot (Telegram).

## Arborescence cible

```
WORKDIR/reverse_proxy/
├── AGENTS.md
├── README.md
├── spec.md                        ← ce fichier
└── scripts/
    └── manage.sh

~/.config/reverse_proxy/
├── projects.json                  ← source de vérité (état persistant)
└── Caddyfile                      ← artefact dérivé, jamais édité à la main
```

> `WORKDIR` est la variable d'environnement pointant vers le répertoire de travail du VPS.
> Si elle n'est pas définie, utiliser `$HOME/workdir` comme fallback.

---

## Dépendances

- **Caddy** installé et accessible via `caddy` dans le PATH
- `jq` installé (manipulation de `projects.json`)
- Droits suffisants pour recharger Caddy (`caddy reload` ou `systemctl reload caddy`)

---

## Fichier `~/.config/reverse_proxy/projects.json`

Source de vérité unique. Jamais écrit à la main — toujours via `manage.sh`.

### Format

```json
{
  "projects": [
    {
      "name": "shootcube",
      "port": 3042,
      "path": "/shootcube/",
      "status": "active"
    },
    {
      "name": "resto",
      "port": 3001,
      "path": "/resto/",
      "status": "active"
    }
  ]
}
```

### Contraintes

- `name` : alphanumérique + tirets, unique
- `port` : entier, range 3000–9999, unique
- `path` : commence et se termine par `/`
- `status` : `active` | `disabled`

---

## Fichier `~/.config/reverse_proxy/Caddyfile`

Artefact généré depuis `projects.json`. Exemple de rendu :

```caddyfile
:80 {
    handle /shootcube/* {
        reverse_proxy localhost:3042
    }

    handle /resto/* {
        reverse_proxy localhost:3001
    }
}
```

Seules les entrées avec `status: "active"` sont incluses dans le rendu.

---

## Script `scripts/manage.sh`

### Usage général

```bash
./scripts/manage.sh <commande> [arguments] [options]
```

### Commandes

#### `add`

```bash
manage.sh add <name> <port> <path> [--no-reload]
```

- Vérifie que `name` n'existe pas déjà dans le registre
- Vérifie que `port` n'est pas déjà utilisé
- Vérifie le format de `path` (commence et finit par `/`)
- Ajoute l'entrée dans `projects.json` avec `status: "active"`
- Génère le `Caddyfile`
- Recharge Caddy (sauf si `--no-reload`)

Exemple :
```bash
manage.sh add shootcube 3042 /shootcube/
```

---

#### `remove`

```bash
manage.sh remove <name> [--no-reload]
```

- Vérifie que `name` existe dans le registre
- Supprime l'entrée de `projects.json`
- Génère le `Caddyfile`
- Recharge Caddy (sauf si `--no-reload`)

---

#### `enable` / `disable`

```bash
manage.sh enable <name> [--no-reload]
manage.sh disable <name> [--no-reload]
```

- Met à jour le champ `status` (`active` / `disabled`)
- Génère le `Caddyfile`
- Recharge Caddy (sauf si `--no-reload`)

---

#### `list`

```bash
manage.sh list
```

Affiche le registre courant sous forme tabulaire :

```
NAME         PORT   PATH           STATUS
shootcube    3042   /shootcube/    active
resto        3001   /resto/        disabled
```

---

#### `reload`

```bash
manage.sh reload
```

- Régénère le `Caddyfile` depuis `projects.json`
- Recharge Caddy (`caddy reload --config ~/.config/reverse_proxy/Caddyfile`)

---

#### `status`

```bash
manage.sh status
```

Affiche :
- État du processus Caddy (running / stopped)
- Liste des routes actives avec leur port
- Path du `Caddyfile` utilisé

---

### Comportement général du script

- Crée `~/.config/reverse_proxy/` et `projects.json` (vide) s'ils n'existent pas au premier lancement
- Affiche un message d'erreur explicite sur stderr et exit 1 en cas d'erreur
- Affiche un message de confirmation sur stdout en cas de succès
- Toutes les opérations de modification sont **atomiques** sur `projects.json` (écriture via fichier tmp + mv)

---

## `AGENTS.md` (contenu attendu)

À créer dans `WORKDIR/reverse_proxy/AGENTS.md`. Doit contenir :

- Description du rôle du projet
- Emplacement de la config : `~/.config/reverse_proxy/`
- Rappel que `Caddyfile` est un artefact dérivé (ne pas éditer directement)
- Liste des commandes `manage.sh` avec exemples
- Conventions : format de `path`, range de ports, unicité de `name`

---

## Cas d'usage de référence

### Ajouter et exposer un nouveau projet

```bash
# Depuis WORKDIR/reverse_proxy/
./scripts/manage.sh add shootcube 3042 /shootcube/
# → projects.json mis à jour
# → Caddyfile régénéré
# → Caddy rechargé
# → http://<VPS_IP>/shootcube/ répond
```

### Désactiver temporairement un projet sans le supprimer

```bash
./scripts/manage.sh disable resto
# → status "disabled" dans projects.json
# → route retirée du Caddyfile actif
```

### Ajouter plusieurs projets sans recharger à chaque fois

```bash
./scripts/manage.sh add proj-a 3010 /proj-a/ --no-reload
./scripts/manage.sh add proj-b 3011 /proj-b/ --no-reload
./scripts/manage.sh reload
```

---

## Ce qui est hors scope de ce projet

- Gestion du cycle de vie des projets applicatifs (start/stop) — chaque projet gère le sien
- SSL / HTTPS — à traiter séparément (Caddy ACME ou certificat manuel)
- Authentification sur les routes exposées
