# Veille et constat — l'agent système Eschaton

Date de consultation : 2026-09-07. Cette passe prépare l'ADR 0005 ; elle ne
valide ni un nouveau framework ni une nouvelle politique de privilèges.

## Sources primaires

- [Hermes Agent, dépôt officiel](https://github.com/NousResearch/hermes-agent).
- [Hermes, outils et ensembles d'outils](https://hermes-agent.nousresearch.com/docs/user-guide/features/tools/).
  La documentation décrit un registre étendu, notamment terminal, fichiers,
  navigateur et mémoire. C'est une référence pertinente pour le versant agent
  généraliste ; aucune garantie d'administration autonome sûre d'Arch n'en
  découle. Aucun code Hermes n'a été installé ou exécuté dans cette passe.
- [Codex app-server](https://learn.chatgpt.com/docs/app-server), consulté lors
  de la même reprise ; protocole 0.139.0 confronté aux schémas de la CLI et au
  runtime ARM dans la VM, preuves `tools/vm-dev.md` §39. La connexion d'abonnement
  constitue un point d'entrée, pas une preuve de réparation du système.

## Écarts constatés dans les sources Eschaton

- `PRODUCT.md` limite explicitement l'action à un catalogue fermé alors que
  ses anti-références rejettent déjà la sidebar sans profondeur système.
- `CodexCore.qml` possède le processus et les messages ; sa durée de vie est
  liée au shell. Il n'existe pas encore de service agent durable séparé.
- `CodexProtocol.js` refuse les outils après `system_status`. La boucle
  autonome diagnostic → réparation est impossible avec cette politique.
- `eschaton-codex-session` désactive shell, édition et autres capacités ;
  `thread/start` utilise un environnement désactivé et un sandbox en lecture
  seule. Le parcours généraliste demandé n'est donc pas couvert non plus.
- `ToolExecutor.qml` et les portes de mise à jour/rollback offrent des briques
  réutilisables ; ils ne constituent pas un moteur d'administration général.

## Ce qui reste à établir avant implémentation élargie

Qualification du runtime Codex avec un vrai compte et les capacités de tâche ;
parcours officiel d'abonnement Claude ; mécanisme local de mandat et autorité
sur les opérations ; persistance/reprise ; mémoire et rétention des données ;
budgets d'inférence ; sources de sécurité et politiques de remédiation ;
procédures de récupération testées. Le choix technique détaillé n'est pas
présenté comme validé par cette seule lecture documentaire.
