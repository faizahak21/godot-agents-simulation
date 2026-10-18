# Campagnes et analyse

## Campagne automatique
Le plan complet des essais A, B, C et de la comparaison a deux sorties est dans [test_protocol.md](test_protocol.md).


1. Dans Godot, ouvrir `scenes/main.tscn` et selectionner `Main`.
2. Dans l’inspecteur, regler `Agent Count`, `Door Width`, `Pillar Enabled` et les autres parametres experimentaux.
	`Upper Right Exit Enabled` active une seconde porte dans le coin superieur droit; les agents choisissent la porte la plus proche. Laisser desactive pour reproduire les experiences A, B et C a une seule porte; activer pour une experience separee a deux sorties.
3. Dans `Campagne automatique`, activer `Campaign Enabled`. Par defaut, la campagne execute les forces 10, 20, ..., 100 avec cinq repetitions, soit 50 simulations completes.
4. Lancer le projet. A chaque simulation terminee, Godot enregistre une ligne puis recharge la scene apres deux secondes.

L’avancement et la graine de base sont conserves dans `user://evacuation_campaign.json`. Si la campagne est interrompue, elle reprend la repetition en cours au prochain lancement. Pour annuler et repartir de zero, arreter le jeu, desactiver `Campaign Enabled`, puis supprimer ce fichier depuis **Projet > Ouvrir le dossier des donnees utilisateur**.

Chaque seed est enregistree dans le CSV recapitulatif. Les lignes `temps_total_s` n’existent que pour les evacuations completees.
Au lancement, les agents commencent assis a leur poste. `Alarm Delay` fixe le compte a rebours avant l’alarme; `Max Reaction Delay` fixe la borne superieure des delais individuels apres l’alarme. Le chronometre de l’evacuation demarre au declenchement de l’alarme et inclut donc le temps de reaction et le lever. Les delais sont reproductibles a seed identique.
Le recapitulatif indique aussi le nombre de sorties configurees et le nombre d’agents partis par chaque sortie. Ne pas melanger dans une meme comparaison les essais a une sortie et ceux a deux sorties.

## Fichiers CSV
Les bureaux ajoutes dans la zone basse sont visuels seulement; ils ne modifient pas les collisions ni les trajectoires mesurees.


Godot ecrit `evacuation_summary.csv` et le dossier `tracking/` dans son dossier de donnees utilisateur. Le recapitulatif est complete; chaque essai possede son CSV de suivi. Copier ces resultats dans un dossier de campagne a part, puis fournir le chemin du recapitulatif au script Python.

## Graphiques Python

Installer les dependances puis lancer l’analyse depuis la racine du projet :

```powershell
python -m pip install -r analysis/requirements.txt
python analysis/analyze_results.py "C:/chemin/vers/evacuation_summary.csv"
```

Les PNG sont crees dans `analysis/output`. Une courbe est ignoree avec un message si le CSV ne contient pas encore plusieurs forces, largeurs ou conditions de pilier.