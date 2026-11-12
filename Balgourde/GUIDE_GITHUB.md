# Mettre Balgourde sur GitHub et publier automatiquement sur CurseForge

Ce dossier est prêt : il contient l'addon et la configuration de publication automatique
(`.github/workflows/release.yml` et `.pkgmeta`). Les fichiers qui commencent par un point sont
peut-être cachés dans l'explorateur Windows (Affichage → Éléments masqués).

## 1. Mettre le code sur GitHub (avec GitHub Desktop, sans ligne de commande)

1. Créez un compte sur github.com, puis installez **GitHub Desktop** (desktop.github.com) et connectez-vous.
2. Dans GitHub Desktop : **File → Add local repository**, choisissez ce dossier `Balgourde`.
   Il propose de « créer un dépôt » : acceptez (**create a repository**).
3. Écrivez un résumé (ex. « Version 0.9.0 ») en bas à gauche, puis **Commit to main**.
4. Cliquez sur **Publish repository**. Cochez « Keep this code private » si vous ne voulez pas que le code soit public
   (la publication automatique fonctionne aussi en privé).

Pour chaque modification ensuite : GitHub Desktop montre les fichiers changés → résumé → **Commit** → **Push origin**.

## 2. Relier GitHub à CurseForge (publication automatique)

1. **Identifiant du projet** : sur la page CurseForge de Balgourde, barre de droite « About Project » → **Project ID**
   (un nombre, ex. 1234567). Dans `Balgourde.toc`, remplacez la ligne
   `# X-Curse-Project-ID: REMPLACER_PAR_L_ID_DU_PROJET`
   par `## X-Curse-Project-ID: 1234567` (deux `#`, et votre nombre). Commit + Push.
2. **Jeton CurseForge** : sur CurseForge, compte → **API Tokens** (wow.curseforge.com/account/api-tokens)
   → créez un jeton et copiez-le. Ne le partagez avec personne.
3. **Secret GitHub** : sur github.com, votre dépôt → **Settings → Secrets and variables → Actions →
   New repository secret**. Nom : `CF_API_KEY`, valeur : le jeton copié.
4. **Droits d'écriture** : dépôt → **Settings → Actions → General → Workflow permissions** →
   cochez **Read and write permissions** → Save.

## 3. Publier une nouvelle version

1. Faites vos modifications, Commit, Push.
2. Sur github.com, dépôt → **Releases → Draft a new release** → **Choose a tag** : tapez `v0.9.1`
   (nouvelle étiquette) → **Publish release**.
3. Dans l'onglet **Actions** du dépôt, la publication démarre (1 à 2 minutes). Le numéro de version
   (`@project-version@` dans le .toc) est remplacé automatiquement par `v0.9.1`.
4. Le fichier arrive sur CurseForge (il repasse par leur vérification) et dans les Releases GitHub.

Pour une version de test : nommez l'étiquette avec `beta` (ex. `v0.9.1-beta`) ; avec `alpha` pour une version alpha.

## Si la publication échoue

- Onglet **Actions** → cliquez sur l'exécution en rouge pour lire l'erreur.
- « resource not accessible by integration » : l'étape 2.4 (droits d'écriture) n'est pas faite.
- Erreur de **version de jeu** : WoW Forever est très récent et l'outil de publication ne le connaît peut-être
  pas encore. Dans ce cas, continuez à envoyer le zip à la main sur CurseForge (le zip est aussi
  disponible dans les Releases GitHub) en attendant une mise à jour de l'outil.

Les dossiers `tools` et les fichiers `PRESENTATION*` et `GUIDE_GITHUB.md` restent sur GitHub
mais ne sont pas mis dans le zip publié (voir `.pkgmeta`).
