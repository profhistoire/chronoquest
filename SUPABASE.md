# Configurer le stockage Supabase

L’application enregistre dans `student_responses` les résultats des mini-jeux et les résultats saisis par l’enseignant. Les réponses détaillées sont conservées dans `answers` au format JSONB. Chaque envoi crée une ligne, avec sa date de réception.

## Mise en place

1. Crée un projet sur [Supabase](https://supabase.com/).
2. Dans **SQL Editor**, vérifie que l’adresse de connexion de l’enseignante à la fin de [`supabase-setup.sql`](./supabase-setup.sql) est bien celle du compte Supabase enseignant, puis exécute le script. Il crée ou complète les tables `student_responses`, `student_roster`, `hub_games`, `game_exercises` et `student_answers`, ainsi que leurs règles d’accès. Le script est additif : il ne supprime pas les tables ni leurs données.
3. Dans les paramètres API du projet, copie l’URL du projet et sa clé publique `anon`/publishable.
4. Remplace les deux valeurs d’exemple dans [`supabase-config.js`](./supabase-config.js).
5. Dans **Authentication → Users**, crée le compte enseignant avec la même adresse que dans le script.
6. Dans **Authentication → Settings**, désactive les inscriptions publiques. Dans **Authentication → Users**, invite ou crée ensuite un compte Supabase pour chaque élève avec son adresse scolaire. Fais définir à chaque élève son mot de passe ChronoQuest via une invitation si possible; ne lui demande pas son mot de passe scolaire. Supabase ne vérifie pas automatiquement le mot de passe du compte scolaire, sauf si un fournisseur d’identité de l’école a été spécifiquement configuré.
7. Après avoir choisi l’adresse HTTPS de publication, ajoute-la dans **Authentication → URL Configuration → Redirect URLs**. Le lien de réinitialisation redirige vers la page d’accueil du Hub; cette URL doit être autorisée par Supabase.
8. Publie `index.html`, `games.json`, `supabase-config.js` et les fichiers des jeux ensemble sur un hébergement web HTTPS. Pour ChronoRomain, conserve `indexchiffresromains.html` à la racine.
9. Connecte-toi comme enseignante, puis importe la liste Excel/CSV (`email, nom, classe`) dans **Liste des Élèves**. La liste est alors partagée dans Supabase et chaque élève peut se connecter avec son adresse et son mot de passe ChronoQuest.
10. Dans Supabase, ouvre **Table Editor → student_responses** pour consulter les résultats et **hub_games** pour consulter les missions.

Dans **Espace enseignant**, connecte-toi avec ce compte pour publier, modifier ou supprimer les missions. Le Hub garde aussi une copie locale et retente de synchroniser les modifications en attente au prochain accès enseignant. Chaque mission peut avoir une image de couverture (PNG, JPEG, WebP ou GIF, maximum 500 Ko); elle est intégrée à la mission et suit ses modifications et suppressions. Les missions disponibles sont chargées depuis Supabase pour tous les élèves. Le mini-jeu lui-même reste du HTML/JavaScript saisi dans le formulaire; les fichiers d’un jeu doivent être hébergés avec le Hub.

## Catalogue de jeux, exercices et réponses

Le Hub lit [`games.json`](./games.json) pour afficher les jeux dans l’espace élève. Chaque entrée précise un `id`, un `title`, une `description` et un `folder`. Pour un nouveau jeu, crée le dossier indiqué avec son fichier `index.html`; ChronoRomain est conservé à la racine sous son nom de fichier actuel. Le bouton de chaque carte ouvre le jeu dans l’iframe du Hub : l’élève reste dans sa session, et le Hub peut recevoir les résultats transmis par le jeu.

Le script ajoute les tables suivantes pour une architecture commune à différents types de jeux :

- `hub_games` : catalogue des jeux. Les colonnes `description` et `game_type` sont ajoutées à la table existante; les anciennes colonnes utilisées par le Hub sont conservées.
- `game_exercises` : exercices liés à un jeu, avec leur niveau, leur consigne et leurs données propres au format JSONB dans `content`.
- `student_answers` : une réponse par enregistrement, liée au compte Supabase (`user_id`), au jeu et à l’exercice; `student_response` contient les détails JSONB et `score` le score entier.

Les exercices sont lisibles par les utilisateurs anonymes et authentifiés; seuls les comptes enseignants autorisés peuvent les créer, modifier ou supprimer. Un élève authentifié peut enregistrer et consulter uniquement ses réponses. La politique de sauvegarde vérifie également que l’exercice appartient au jeu indiqué. Les enseignants autorisés peuvent consulter toutes les réponses. Les anciennes politiques et la table `student_responses` restent en place.

Comme la lecture de `game_exercises` est publique, ne place pas de corrigé confidentiel ou de réponse attendue secrète dans `content`. De même, un score envoyé directement par un jeu dans le navigateur peut être falsifié; un score nécessitant une garantie devra être calculé ou vérifié côté serveur.

Ces nouvelles tables fournissent le schéma et les permissions, mais les jeux et le code du Hub existants utilisent encore `student_responses`. Pour que les jeux écrivent dans `student_answers` ou chargent les exercices depuis `game_exercises`, leur code devra être adapté à ce nouveau format.

La clé publique `anon` est destinée à être utilisée dans le navigateur. La lecture des missions est publique, mais leur gestion et l’import de la liste des élèves requièrent un utilisateur Supabase authentifié dont l’adresse figure dans `hub_teacher_access`. **N’utilise jamais la clé `service_role` ou une clé secrète dans ce fichier.**

## Réinitialisation enseignant des mots de passe

L’onglet **Réinitialisation des mots de passe** contient un formulaire pour choisir un élève importé et définir un mot de passe provisoire d’au moins 12 caractères. Le bouton **Générer un mot de passe** crée un mot de passe aléatoire individuel de 20 caractères; tu peux aussi en saisir un manuellement. Le formulaire appelle `supabase.functions.invoke('reset-student-password')`. La fonction serveur [index.ts](./supabase/functions/reset-student-password/index.ts) revérifie la session, appelle `is_hub_teacher()`, confirme que l’adresse est dans `student_roster`, puis utilise `auth.admin.updateUserById`. Le mot de passe n’est pas écrit dans les journaux ni renvoyé par la fonction.

N’utilise pas un mot de passe commun à toute la classe : chaque élève doit avoir un mot de passe différent. Transmets le mot de passe généré par un canal privé et demande à l’élève de le remplacer.

L’API Admin et la clé `SUPABASE_SERVICE_ROLE_KEY` ne doivent jamais être utilisées dans le navigateur. La fonction serveur exige les secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY`; configure-les dans **Supabase → Edge Functions → Secrets**. Ne colle pas la clé service-role dans un fichier du site, dans le code HTML/JS client ou dans le dépôt Git.

Pour déployer la fonction avec Supabase CLI, depuis le dossier du Hub :

```powershell
supabase login
supabase link --project-ref dpmbygacgygczrnvozjb
supabase functions deploy reset-student-password
```

Le mot de passe provisoire ne s’expire pas automatiquement. Transmets-le à l’élève par un canal privé et demande-lui de le remplacer; le lien « Mot de passe oublié ? » nécessite un fournisseur SMTP configuré.

## Format des réponses des mini-jeux

À la fin d’un jeu, transmets le score et les réponses avec `postMessage` :

```js
parent.postMessage({
  type: "chronoquest-result",
  score: 16,
  maxScore: 20,
  competencies: {
    C1: 80,
    C2: 75,
    C3: 90,
    C4: 85
  },
  answers: [
    { question: "q1", answer: "Réponse de l’élève" },
    { question: "q2", answer: "Autre réponse" }
  ]
}, "*");
```

`answers` accepte un objet ou un tableau JSON jusqu’à 20 Ko. Si un jeu ne transmet pas `answers`, le score est quand même enregistré et ce champ reste vide. Les résultats saisis manuellement par l’enseignant sont enregistrés avec `source = teacher` et sans réponses détaillées.

Dans **Détective Doc** ([`jeux/index.html`](./jeux/index.html)), le bouton « Enregistrer mes résultats » transmet le score et les réponses au Hub. Le Hub utilise la session élève déjà authentifiée pour renseigner `student_id` dans `student_responses`; le jeu n’accède pas directement à Supabase. L’enregistrement fonctionne lorsque le jeu est lancé depuis l’espace élève du Hub, pas lorsqu’on ouvre son fichier seul. L’aperçu enseignant refuse la sauvegarde.

Les quatre compétences sont enregistrées sous les clés `C1`, `C2`, `C3` et `C4`, avec des valeurs de 0 à 100. Les anciens jeux qui envoient encore `observation`, `analyse` et `comprehension` sont acceptés temporairement et convertis en `C1`, `C2` et `C3`; `C4` restera vide jusqu’à ce que le jeu la transmette.

ChronoRomain transmet chaque réponse au Hub avec `postMessage`. Le Hub associe l’élève déjà connecté (adresse e-mail, nom et classe) et insère une ligne dans `student_responses` pour chaque question. Le champ `answers` contient le niveau, la question, la réponse de l’élève, la bonne réponse et l’indication de réussite. Il faut lancer ChronoRomain depuis le Hub pour que les réponses soient enregistrées.

## Connexion élève et confidentialité

Chaque élève se connecte avec son compte Supabase (adresse scolaire + mot de passe ChronoQuest). Il ne suffit plus de saisir une adresse. Les comptes élèves doivent être créés dans **Authentication → Users**; n’active pas l’inscription publique. Importe la liste officielle depuis l’espace enseignant afin que Supabase puisse vérifier l’adresse et fournir le nom et la classe.

Si un élève oublie son mot de passe, il saisit son adresse sur la page d’accueil puis clique **Mot de passe oublié ?**. Supabase lui envoie un lien de réinitialisation. En l’ouvrant depuis le site publié, il pourra choisir et confirmer un nouveau mot de passe. L’adresse de publication doit être ajoutée dans **Authentication → URL Configuration → Redirect URLs**; cette fonction ne marche pas quand on ouvre le fichier HTML directement (`file://`).

La sécurité est appliquée par les politiques RLS de Supabase : un élève ne peut lire que les lignes de `student_responses` dont `student_id` correspond à son propre compte. Un élève ne peut enregistrer que ses propres réponses, avec l’adresse de sa session authentifiée. Seuls les comptes dont l’adresse figure dans `hub_teacher_access` peuvent lire tous les résultats ou modifier la liste. Les accès anonymes aux réponses sont retirés. Les anciens résultats sont rattachés au compte correspondant lorsque le script SQL trouve une adresse identique dans Supabase Auth; les résultats sans compte correspondant restent visibles à l’enseignante, mais pas dans un bilan élève.

La barre **MODE TEST** et ses vues **Élève** / **Enseignant** restent disponibles uniquement pendant une session authentifiée et vérifiée comme enseignante. La vue élève est un aperçu enseignant du premier élève de la liste importée; les résultats de jeu émis depuis cet aperçu ne sont pas enregistrés.

Les comptes Supabase ne sont pas automatiquement les comptes de messagerie de l’école : le mot de passe scolaire ne sera reconnu que si l’établissement configure un fournisseur d’identité compatible. Ne partage jamais les mots de passe des élèves et vérifie les règles de l’établissement concernant le consentement, la durée de conservation et la suppression de leurs données.
