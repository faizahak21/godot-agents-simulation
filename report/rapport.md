# Simulation d’evacuation d’un bureau

## Problematique

Comment des agents qui se dirigent individuellement vers une sortie peuvent-ils former un blocage collectif, et comment la force motrice, la largeur de porte et un obstacle modifient-ils l’evacuation ?

## Modele

La scene represente un bureau en vue plongeante, avec un couloir, deux salles de reunion, des postes de travail, une ou deux sorties et des agents rigides. Les agents commencent assis; une alarme survient apres un compte a rebours, puis chacun reagit avec un delai individuel reproductible avant de se lever et d’evacuer. Le temps total est mesure depuis l’alarme et inclut ces delais. Chaque agent poursuit des points de passage, subit les collisions physiques et ajuste sa direction selon ses voisins. Le script ajoute egalement une faible agitation laterale et une regle d’evitement du pilier quand celui-ci est active.

Les parametres principaux sont le nombre d’agents, la force motrice, la vitesse desiree, la largeur de la porte, le frottement et la position/diametre du pilier. Une sortie supplementaire peut etre activee dans le coin superieur droit; les agents choisissent l’itineraire vers la sortie la plus proche. Noter le nombre de sorties utilisees et les valeurs effectivement retenues pour chaque campagne.

## Protocole experimental

Pour chaque configuration, realiser cinq repetitions avec des graines distinctes et conserver les memes autres parametres. Les campagnes automatiques sont configurees dans l’inspecteur du noeud Main. Les mesures temporelles sont ecrites dans `evacuation_tracking.csv`; les simulations terminees sont ajoutees dans `evacuation_summary.csv`.

### Experience A : force motrice

60 agents, porte de 1,5 m, sans pilier. Tester les forces de 10 a 100 par pas de 10, cinq repetitions par force. Rapporter moyenne et ecart-type du temps total.

### Experience B : largeur de porte

60 agents, force moyenne fixee, sans pilier. Tester plusieurs largeurs entre 0,8 et 3 m. Comparer le debit moyen `agents initiaux / temps total`.

### Experience C : obstacle

Comparer avec/sans pilier a faible et forte force, avec les memes graines entre conditions. Rapporter les temps moyens et leur variabilite.

### Extension : deux sorties

Activer `Upper Right Exit Enabled` pour ouvrir une seconde sortie en haut a droite. Les agents choisissent la sortie la plus proche; les CSV rapportent le nombre d’agents sortis par chaque porte. Analyser cette configuration separement des experiences a sortie unique.

## Resultats

Insérer ici les graphiques generes par `analysis/analyze_results.py`, les tailles d’echantillon et les moyennes/ecarts-types. Ne pas conclure a une tendance en U avant d’avoir des repetitions suffisantes pour plusieurs forces.
Les resultats historiques collectes avant l’ajout de l’alarme ont `alarme_delai_s=0` et `reaction_max_s=0`; les nouvelles repetitions utilisent les valeurs d’alarme configurees et doivent etre analysees comme un protocole distinct.

## Interpretation

Discuter les contacts, le debit a la porte, la densite mesuree et les blocages visibles. Comparer les observations au diagramme dans `report/mechanism_diagram.md`.

Le cycle de vie UML d’un agent est illustre dans [agent_state_diagram.svg](agent_state_diagram.svg) et decrit dans [agent_state_diagram.md](agent_state_diagram.md).

## Limites

- Les agents connaissent leur itineraire et la sortie.
- Les delais de reaction sont simples et uniformement tires entre 0,5 s et la limite configuree; aucun comportement social riche ni recherche de proches n’est modele.
- Le frottement et les masses ne sont pas calibres sur des mesures reelles.
- Les agents sont des corps rigides stylises; le mobilier est en partie uniquement visuel.
- Les resultats sont qualitatifs et ne constituent pas des predictions d’une evacuation reelle.