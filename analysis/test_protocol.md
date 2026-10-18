# Protocole de tests

## Reglages fixes

Pour toutes les simulations comparables, garder :

- 60 agents.
- Compte a rebours d’alarme : 5 s.
- Delai de reaction maximal : 3 s.
- Duree maximale : 180 s apres l’alarme.
- Meme disposition du bureau et memes regles physiques.
- Cinq repetitions par configuration, avec des graines differentes.
- Laisser les agents terminer l’evacuation. Si `agents_sortis` ne change plus pendant 10 s, noter le run comme bloque/incomplet; ne pas l’utiliser comme un temps total complet.

Le chronometre du CSV commence a l’alarme et inclut le delai de reaction et le lever. Comparer uniquement les lignes ayant les memes valeurs `alarme_delai_s`, `reaction_max_s` et `sorties_configurees`.

## Test A : effet de la force

But : chercher si augmenter la force accelere d’abord l’evacuation, puis finit par la ralentir.

- Sortie en haut a droite : desactivee.
- Largeur de porte : 1,5 m.
- Pilier : desactive.
- Forces : 10, 20, 30, 40, 50, 60, 70, 80, 90 et 100.
- Repetitions : 5 par force, soit 50 simulations.

Activer `Campaign Enabled`, conserver les dix valeurs dans `Campaign Forces` et `Campaign Repetitions = 5`. Laisser la campagne se terminer. Calculer pour chaque force le temps moyen, l’ecart-type et le debit moyen (`60 / temps_total_s`).

## Test B : largeur de la porte

But : mesurer l’effet de la largeur sur le debit.

### Reglages a faire une seule fois

Dans Godot, arreter le jeu et selectionner `Main` dans l’arbre de scene. Dans l’Inspecteur, regler :

- `Agent Count` : 60.
- `Agent Force Gain` : la force optimale trouvee au test A; si A n’est pas termine, mettre provisoirement 40 et garder 40 pour les six largeurs.
- `Pillar Enabled` : desactive.
- `Upper Right Exit Enabled` : desactive. Il est normal de ne voir que la sortie du bas pendant ce test.
- `Campaign Enabled` : desactive.
- `Duree Max` : 180 s.

Ouvrir **Projet > Ouvrir le dossier des donnees utilisateur**. Supprimer `evacuation_summary.csv` une seule fois au debut du test B, et vider le contenu du dossier `tracking/`. Ne pas effacer ces resultats entre les largeurs : on veut rassembler les 30 essais dans le meme recapitulatif. Sauvegarder la scene avec Ctrl+S apres le reglage des valeurs.

### Les 30 lancements

Faire les largeurs dans cet ordre : **0,8; 1,0; 1,2; 1,5; 2,0; 3,0 m**. Pour chacune :

1. Arreter le jeu s’il tourne, puis selectionner `Main`.
2. Changer `Door Width` pour la largeur du groupe en cours.
3. Mettre `Random Seed` a 1 et sauvegarder avec Ctrl+S.
4. Lancer avec F5. Attendre la fin de l’evacuation ou le message de timeout avant de continuer.
5. Refaire les etapes avec les seeds 2, 3, 4 et 5.
6. Passer a la largeur suivante et reprendre les seeds 1 a 5.

Exemple : porte 0,8 m avec seeds 1, 2, 3, 4, 5, puis porte 1,0 m avec les memes seeds 1, 2, 3, 4, 5, et ainsi de suite. Il y a donc **30 lancements F5**. Chaque lancement ajoute une ligne au recapitulatif et cree un fichier de suivi distinct dans `tracking/`.

### Analyse

Verifier qu’il y a 30 lignes de donnees dans `evacuation_summary.csv`, soit cinq pour chacune des six largeurs. Pour chaque essai complet, calculer le debit `60 / temps_total_s`, puis comparer le debit moyen et l’ecart-type par largeur. Garder les lignes `timeout` dans le bilan des echecs, mais ne pas les utiliser comme des temps d’evacuation completes.

## Test C : effet du pilier

But : comparer les evacuations avec et sans obstacle a faible et forte force.

- Sortie en haut a droite : desactivee.
- Largeur : 1,5 m.
- Forces : 20 et 100.
- Pilier : desactive puis active; diametre 0,8 m, a 1,8 m de la sortie.
- Repetitions : 5 par combinaison, soit 20 simulations.

Utiliser `agent_force_gain = 20` puis `100`, 5 repetitions par condition. Pour chaque force, faire un groupe sans pilier et un groupe avec pilier. Utiliser les memes seeds 1 a 5 dans les quatre groupes. Comparer les moyennes et ecarts-types; ne pas conclure sur une condition avec moins de cinq evacuations completes.

## Test D : une sortie ou deux

But : observer le partage des flux et voir si la seconde sortie reduit la congestion.

- 60 agents, force 20, porte 1,5 m, sans pilier.
- Comparer `Upper Right Exit Enabled` desactive puis active.
- Faire 5 simulations completes par condition.

Comparer le temps total, le debit, `sorties_basses` et `sorties_hautes`. Garder ces resultats separes des tests A, B et C, qui utilisent une seule sortie.

## Mesures a relever

`evacuation_summary.csv` fournit le temps total, les reglages, la graine et le nombre d’agents sortis par chaque porte. Chaque fichier dans `tracking/` montre l’evolution seconde par seconde d’un essai : agents restants/sortis, debit et densite maximale mesuree pres des sorties. Son nom contient la seed et les principaux reglages.

Un run s’arrete automatiquement apres `duree_max = 180` s de temps d’evacuation et est marque `timeout` avec son nombre d’agents restants. Ne pas inclure ces lignes dans les moyennes de temps complet; compter et rapporter les timeouts a part.

Pour chaque condition, rapporter : nombre de repetitions completes, moyenne, ecart-type, minimum, maximum, et eventuels blocages. La moyenne seule ne suffit pas lorsque les repetitions varient beaucoup.

## Precautions de comparaison

- Les anciens essais sans alarme ont `alarme_delai_s=0` et `reaction_max_s=0`; ils ne sont pas directement comparables aux nouveaux essais.
- Ne pas melanger les essais a une sortie avec ceux a deux sorties.
- Ne changer qu’un facteur entre deux groupes.
- Si une campagne est interrompue puis qu’on change sa configuration, desactiver `Campaign Enabled` et supprimer `user://evacuation_campaign.json` avant de repartir, pour ne pas reprendre l’ancien index d’essai.
