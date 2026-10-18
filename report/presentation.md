# Présentation du projet — Simulation d’évacuation

Durée suggérée : **8 à 10 minutes**.

Diapo prête à insérer pour les résultats du test B : [slide_test_b.svg](slide_test_b.svg).

## 1. Sujet et problématique — 1 min

Présenter le projet : une simulation d’évacuation dans un bureau avec des agents autonomes.

Question de recherche :

> Comment des personnes qui cherchent individuellement une sortie peuvent-elles créer un blocage collectif, et comment la largeur de la porte influence-t-elle l’évacuation ?

## 2. Modèle du système — 1 min

Décrire brièvement les éléments simulés :

- Un bureau avec des postes de travail et des salles de réunion.
- 60 agents qui commencent assis.
- Une alarme, suivie d’un délai de réaction individuel.
- Des portes, des collisions et une sortie.
- Des mesures enregistrées dans des fichiers CSV.

Montrer le diagramme de cas d’utilisation réalisé dans Modelio pour présenter les fonctions principales du simulateur.

## 3. Comportement d’un agent — 1 min

Présenter le cycle de vie :

**Assis → attend l’alarme → réagit → se lève → évacue → sorti**

Si l’évacuation n’est pas terminée dans le délai maximal, l’essai est noté **timeout**. Le diagramme d’états est fourni comme image SVG de référence; il n’a pas été créé dans Modelio.

## 4. Protocole expérimental — 1 min

Présenter le test B :

- 60 agents.
- Une seule sortie, celle du bas.
- Aucun pilier.
- Force fixée à 40 provisoirement, en attendant la force optimale du test A.
- Six largeurs de porte : 0,8; 1,0; 1,2; 1,5; 2,0 et 3,0 m.
- Cinq graines aléatoires par largeur.

Préciser qu’une seule variable, la largeur de la porte, varie entre les groupes.

## 5. Résultats — 2 min

Montrer le graphique du débit moyen selon la largeur de la porte. Pour chaque largeur, le débit d’un essai complet est calculé ainsi :

$$
\text{Débit} = \frac{60\ \text{agents}}{\text{temps total d’évacuation}}
$$

Résultats observés :

| Largeur de porte | Essais complets | Timeouts | Temps moyen des essais complets |
|---:|---:|---:|---:|
| 0,8 m | 1 | 4 | 25,783 s* |
| 1,0 m | 5 | 0 | 24,112 s |
| 1,2 m | 5 | 0 | 19,138 s |
| 1,5 m | 4 | 1 | 17,763 s |
| 2,0 m | 5 | 0 | 18,140 s |
| 3,0 m | 5 | 0 | 17,380 s |

\* Pour 0,8 m, un seul résultat complet est exploitable après exclusion d’une ligne dupliquée avec la même seed. La moyenne est donc très provisoire.

Commentaire possible :

> Le débit augmente globalement quand la porte s’élargit, mais la relation n’est pas parfaitement régulière ni proportionnelle. La porte de 0,8 m entraîne quatre timeouts sur cinq; à 1,5 m, un essai sur cinq a également expiré.

Préciser que la force de 40 est provisoire si le test A n’a pas encore établi la force optimale.

## 6. Interprétation et limites — 1 à 2 min

Interpréter les résultats en lien avec la congestion et les blocages observés devant les portes. Les résultats sont des tendances de simulation, pas des prédictions d’une évacuation réelle.

Limites à mentionner :

- Les agents et leurs règles de déplacement sont simplifiés.
- Les paramètres physiques ne sont pas calibrés sur des mesures réelles.
- Le mobilier ne représente pas nécessairement des obstacles physiques dans les déplacements.
- La variabilité des départs influence les résultats; c’est pourquoi plusieurs seeds sont utilisées.
- Les timeouts ne sont pas inclus dans les moyennes des évacuations complètes, mais doivent être présentés séparément.

## 7. Conclusion et suite — 30 s

Résumer ce que le test B suggère sur l’influence de la largeur de la porte. Annoncer les étapes suivantes :

- Test A : effet de la force motrice.
- Test C : comparaison avec et sans pilier.

## Démonstration à préparer

- Ouvrir le projet Godot avant le début de la présentation.
- Préparer une simulation courte à lancer si le temps le permet.
- Ouvrir le diagramme de cas d’utilisation Modelio.
- Ouvrir le diagramme d’états SVG : [agent_state_diagram.svg](agent_state_diagram.svg).
- Ouvrir le graphique Excel du test B; enlever la légende en double et ajouter une note sur les timeouts.
- Garder le CSV récapitulatif accessible pour montrer les valeurs brutes.
