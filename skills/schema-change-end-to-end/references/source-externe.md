# Source externe : on ne modifie que la transformation

Source externe : base ou application que l'équipe ne maîtrise pas (ERP, outil de ticketing, fournisseur de données). On ne propose jamais d'y changer un schéma, une clé ou une règle de gestion.

## Ce qui est modifiable

| Couche | Modifiable | Moyen |
|---|---|---|
| Réplication | Oui, si l'outil de capture nous appartient | Liste des tables, snapshot |
| Bronze vers silver | Oui | `columns` : renommage, ajout, retrait d'une colonne |
| Gold | Oui | `column_mapping`, requêtes de dimensions, `computed_columns`, `lookups`, `post_filter` |
| Modèle sémantique | Oui | Colonnes et mesures |
| API et SPA | Oui, si elles consomment la donnée transformée | S'adaptent à ce que la transformation produit |
| Source | Non | Signaler l'écart, ne rien proposer d'y changer |

## Procédure

1. **Constater l'écart par lecture** : comparer le schéma silver actuel (`DESCRIBE TABLE`) avec la nouvelle structure de la source. Ne pas supposer le nouveau schéma : demander à l'utilisateur ou lire un exemple de données.
2. **Absorber dans la transformation** : les différences de nom ou de type se règlent dans `columns` ou `column_mapping` (renommage, conversion avec `CAST` dans une requête de dimension). Une valeur manquante se règle avec `COALESCE` ou une valeur par défaut explicite et documentée.
3. **Préserver les noms Gold** : garder les noms de colonnes Gold inchangés pour que le modèle sémantique et les consommateurs ne bougent pas.
4. **Préserver les SK** : ne pas changer `merge_key` d'une dimension existante, sauf si la clé métier de la source change réellement.
5. **Protéger contre l'amont vide ou incomplet** : ne pas ajouter `allow_empty: true` pour faire taire une erreur. Une requête vide qui échoue protège la table cible.
6. **Documenter les hypothèses** : dans le compte rendu, lister ce qui est supposé sur la source (types, unicité, nullité) et qui n'a pas pu être vérifié.

## Quand l'API ou la SPA sont concernées

Elles ne le sont que lorsque le Gold ou une API appelle la donnée externe. Dans ce cas :

- Un appel à une API externe passe par une interface proxy du dépôt API, avec des modèles qui reflètent exactement la réponse de l'API externe. Adapter les modèles et le mapper, pas le DTO exposé, sauf décision de l'utilisateur.
- Aucune règle de la source n'est dupliquée dans la SPA : elle consomme ce que l'API expose.

## À signaler dans le compte rendu

- Les écarts de la source qui restent sans traitement et nécessitent un tiers.
- Les valeurs par défaut introduites, avec leur effet sur les chiffres.
- Les contrôles de qualité à ajouter côté Gold pour détecter une nouvelle dérive.
