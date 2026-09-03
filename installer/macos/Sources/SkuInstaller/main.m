#import <Cocoa/Cocoa.h>

/* UI language (de/en/fr), mirroring the Windows installer's Loc.cs: stored
   choice first (shared with the backend script via the preferences domain),
   then the system UI language, then English. L() falls back to English so a
   missing key never blanks a control. */
static NSString *UILang = @"en";
static NSDictionary<NSString*,NSDictionary<NSString*,NSString*>*> *LocTables(void) {
 static NSDictionary *t; static dispatch_once_t once;
 dispatch_once(&once, ^{ t = @{
 @"de": @{
  @"app.title": @"Sku Installer und Updater",
  @"role.heading": @"Überschrift",
  @"status.checking": @"Der Status wird geprüft.",
  @"games.acc": @"Installierte WoW-Version",
  @"path.none": @"Noch kein AddOns-Ordner ausgewählt.",
  @"pack.de": @"Deutsch", @"pack.fastde": @"Deutsch schnell", @"pack.en": @"Englisch",
  @"pack.acc": @"Sprachpaket",
  @"label.uilang": @"Sprache der Oberfläche",
  @"login.title": @"WoW Login Tool für Hammerspoon installieren und aktualisieren",
  @"managed.fmt": @"%@ verwalten – verfügbar %@",
  @"name.pawn": @"Pawn Ausrüstungsvergleich",
  @"name.gtfo": @"GTFO Gefahrenwarnung",
  @"name.bugsack": @"BugSack und BugGrabber",
  @"help.questie": @"Installiert und aktualisiert die Anniversary-Version von Questie über CurseForge.",
  @"help.atlas": @"Installiert und aktualisiert AtlasLootClassic über CurseForge; die eine Fassung deckt Anniversary und Classic Era ab.",
  @"help.details": @"Installiert und aktualisiert Details Damage Meter über CurseForge; die eine Fassung deckt Anniversary und Classic Era ab.",
  @"help.pawn": @"Installiert und aktualisiert Pawn über GitHub; jeder Client erhält die passende Fassung. Standardmäßig abgewählt.",
  @"help.dbm": @"Installiert und aktualisiert DBM über GitHub; jeder Client erhält die passenden Schlachtzugs- und Dungeon-Module.",
  @"help.gtfo": @"Installiert und aktualisiert GTFO, die akustische Warnung vor Bodeneffekten, über CurseForge.",
  @"help.bugsack": @"Installiert und aktualisiert die Fehlererfassung BugSack samt BugGrabber über GitHub und CurseForge.",
  @"btn.update": @"Sku und ausgewählte AddOns installieren oder aktualisieren",
  @"btn.repair": @"Installation vollständig reparieren",
  @"btn.cancel": @"Aktualisierung abbrechen",
  @"btn.inventory": @"Installierte AddOns anzeigen",
  @"help.inventory": @"Erstellt eine alphabetisch sortierte, rein lesende Übersicht aller erkannten AddOn-Pakete, Versionen und Quellen.",
  @"btn.browse": @"AddOns-Ordner manuell auswählen",
  @"btn.logs": @"Diagnosepaket erstellen",
  @"btn.check": @"Installer-Aktualisierung prüfen",
  @"btn.quit": @"Beenden",
  @"acc.progress": @"Fortschritt",
  @"output.ready": @"Bereit.",
  @"acc.output": @"Installationsdetails",
  @"label.wow": @"WoW-Version",
  @"label.pack": @"Sprachpaket",
  @"label.managed": @"Verwaltete AddOns für Anniversary und Classic Era",
  @"label.details": @"Details",
  @"flavor.manual": @"Manueller AddOns-Ordner",
  @"suffix.sku": @" – Sku installiert",
  @"help.managed.on": @"Die ausgewählten AddOns werden zusammen mit Sku aktualisiert; jeder Client erhält die zu ihm passende Fassung.",
  @"help.managed.off": @"Die zusätzliche AddOn-Verwaltung ist für Anniversary und Classic Era verfügbar.",
  @"summary.uptodate": @"Alle AddOns sind auf dem neuesten Stand.",
  @"summary.one": @"Für %@ ist ein Update verfügbar.",
  @"summary.many": @"Für %@ sind Updates verfügbar.",
  @"word.and": @"und",
  @"word.dot": @" Punkt ",
  @"word.new": @"neu",
  @"status.refresh": @"Der Aktualisierungsstatus aller ausgewählten AddOns wird geprüft.",
  @"panel.title": @"AddOns-Ordner auswählen",
  @"panel.msg": @"Wähle den WoW-Versionsordner oder Interface/AddOns.",
  @"panel.prompt": @"Auswählen",
  @"alert.invalidfolder.title": @"Ungültiger Ordner",
  @"alert.invalidfolder.body": @"Bitte wähle einen WoW-Versionsordner oder Interface/AddOns.",
  @"alert.folderunusable": @"Ordner nicht verwendbar",
  @"busy.start": @"Vorgang wird gestartet …\n",
  @"alert.startfailed": @"Vorgang konnte nicht gestartet werden",
  @"status.repairing": @"Vollständige Reparatur läuft. Bitte warten.",
  @"status.updating": @"Sku und ausgewählte AddOns werden aktualisiert. Bitte warten.",
  @"alert.done.title": @"Aktualisierung abgeschlossen",
  @"alert.fail.title": @"Aktualisierung fehlgeschlagen",
  @"alert.done.repair": @"Sku und alle ausgewählten AddOns wurden vollständig neu installiert.",
  @"alert.done.update": @"Sku und die ausgewählten Anniversary-AddOns wurden erfolgreich installiert oder aktualisiert.",
  @"alert.fail.body": @"Die vorherigen Versionen wurden bei einem Austauschfehler wiederhergestellt. Erstelle bei Bedarf ein Diagnosepaket.",
  @"status.canceling": @"Aktualisierung wird abgebrochen.",
  @"status.inventory": @"Die installierten AddOns werden erfasst.",
  @"inv.none": @"Es wurden keine AddOns erkannt.",
  @"acc.inventory": @"Installierte AddOns",
  @"status.inv.done": @"Die AddOn-Liste wurde erstellt.",
  @"status.inv.fail": @"Die AddOn-Liste konnte nicht erstellt werden.",
  @"alert.logs.done": @"Diagnosepaket erstellt",
  @"alert.logs.path": @"Die ZIP-Datei liegt hier:\n%@",
  @"alert.logs.fail.title": @"Diagnose fehlgeschlagen",
  @"alert.logs.fail.body": @"Das Paket konnte nicht erstellt werden.",
  @"alert.check.fail.title": @"Prüfung fehlgeschlagen",
  @"alert.check.fail.body": @"Die Installer-Version konnte momentan nicht geprüft werden.",
  @"alert.selfupdate.title": @"Neue Installer-Version verfügbar",
  @"alert.selfupdate.body": @"Version %@ kann aus dem offiziellen Repository geladen, per SHA-256 und Developer-ID-Signatur geprüft und installiert werden.",
  @"btn.updatenow": @"Jetzt aktualisieren",
  @"btn.later": @"Später",
  @"alert.selfupdate.fail.title": @"Installer-Aktualisierung fehlgeschlagen",
  @"alert.selfupdate.fail.body": @"Das vorhandene Programm wurde nicht ersetzt. Das heruntergeladene Paket war nicht verfügbar oder bestand die Sicherheitsprüfung nicht.",
  @"alert.uptodate.title": @"Installer ist aktuell",
  @"alert.uptodate.body": @"Es ist keine neuere veröffentlichte macOS-Version verfügbar.",
  @"btn.close": @"Schließen",
  @"alert.running.title": @"Aktualisierung läuft",
  @"alert.running.body": @"Brich sie zuerst mit dem Schalter Aktualisierung abbrechen ab.",
 },
 @"en": @{
  @"app.title": @"Sku Installer & Updater",
  @"role.heading": @"Heading",
  @"status.checking": @"Checking the status.",
  @"games.acc": @"Installed WoW version",
  @"path.none": @"No AddOns folder selected yet.",
  @"pack.de": @"German", @"pack.fastde": @"German fast", @"pack.en": @"English",
  @"pack.acc": @"Voice pack",
  @"label.uilang": @"Interface language",
  @"login.title": @"Install and update the WoW login tool for Hammerspoon",
  @"managed.fmt": @"Manage %@ – available %@",
  @"name.pawn": @"Pawn gear comparison",
  @"name.gtfo": @"GTFO danger warning",
  @"name.bugsack": @"BugSack and BugGrabber",
  @"help.questie": @"Installs and updates the Anniversary version of Questie via CurseForge.",
  @"help.atlas": @"Installs and updates AtlasLootClassic via CurseForge; the one build covers Anniversary and Classic Era.",
  @"help.details": @"Installs and updates Details Damage Meter via CurseForge; the one build covers Anniversary and Classic Era.",
  @"help.pawn": @"Installs and updates Pawn via GitHub; each client gets the matching build. Deselected by default.",
  @"help.dbm": @"Installs and updates DBM via GitHub; each client gets the matching raid and dungeon modules.",
  @"help.gtfo": @"Installs and updates GTFO, the audible warning for ground effects, via CurseForge.",
  @"help.bugsack": @"Installs and updates the error capture BugSack together with BugGrabber via GitHub and CurseForge.",
  @"btn.update": @"Install or update Sku and the selected AddOns",
  @"btn.repair": @"Repair the installation completely",
  @"btn.cancel": @"Cancel the update",
  @"btn.inventory": @"Show installed AddOns",
  @"help.inventory": @"Creates an alphabetically sorted, read-only overview of all detected AddOn packages, versions and sources.",
  @"btn.browse": @"Choose the AddOns folder manually",
  @"btn.logs": @"Create a diagnostic package",
  @"btn.check": @"Check for installer updates",
  @"btn.quit": @"Quit",
  @"acc.progress": @"Progress",
  @"output.ready": @"Ready.",
  @"acc.output": @"Installation details",
  @"label.wow": @"WoW version",
  @"label.pack": @"Voice pack",
  @"label.managed": @"Managed AddOns for Anniversary and Classic Era",
  @"label.details": @"Details",
  @"flavor.manual": @"Manual AddOns folder",
  @"suffix.sku": @" – Sku installed",
  @"help.managed.on": @"The selected AddOns are updated together with Sku; each client gets the build that matches it.",
  @"help.managed.off": @"The additional AddOn management is available for Anniversary and Classic Era.",
  @"summary.uptodate": @"All AddOns are up to date.",
  @"summary.one": @"An update is available for %@.",
  @"summary.many": @"Updates are available for %@.",
  @"word.and": @"and",
  @"word.dot": @" dot ",
  @"word.new": @"new",
  @"status.refresh": @"Checking the update status of all selected AddOns.",
  @"panel.title": @"Choose the AddOns folder",
  @"panel.msg": @"Choose the WoW version folder or Interface/AddOns.",
  @"panel.prompt": @"Select",
  @"alert.invalidfolder.title": @"Invalid folder",
  @"alert.invalidfolder.body": @"Please choose a WoW version folder or Interface/AddOns.",
  @"alert.folderunusable": @"Folder not usable",
  @"busy.start": @"Starting the operation …\n",
  @"alert.startfailed": @"The operation could not be started",
  @"status.repairing": @"Full repair is running. Please wait.",
  @"status.updating": @"Sku and the selected AddOns are being updated. Please wait.",
  @"alert.done.title": @"Update finished",
  @"alert.fail.title": @"Update failed",
  @"alert.done.repair": @"Sku and all selected AddOns were completely reinstalled.",
  @"alert.done.update": @"Sku and the selected Anniversary AddOns were installed or updated successfully.",
  @"alert.fail.body": @"The previous versions were restored after a replacement error. Create a diagnostic package if needed.",
  @"status.canceling": @"Canceling the update.",
  @"status.inventory": @"Collecting the installed AddOns.",
  @"inv.none": @"No AddOns were detected.",
  @"acc.inventory": @"Installed AddOns",
  @"status.inv.done": @"The AddOn list was created.",
  @"status.inv.fail": @"The AddOn list could not be created.",
  @"alert.logs.done": @"Diagnostic package created",
  @"alert.logs.path": @"The ZIP file is here:\n%@",
  @"alert.logs.fail.title": @"Diagnostics failed",
  @"alert.logs.fail.body": @"The package could not be created.",
  @"alert.check.fail.title": @"Check failed",
  @"alert.check.fail.body": @"The installer version could not be checked right now.",
  @"alert.selfupdate.title": @"New installer version available",
  @"alert.selfupdate.body": @"Version %@ can be downloaded from the official repository, verified via SHA-256 and Developer ID signature, and installed.",
  @"btn.updatenow": @"Update now",
  @"btn.later": @"Later",
  @"alert.selfupdate.fail.title": @"Installer update failed",
  @"alert.selfupdate.fail.body": @"The existing application was not replaced. The downloaded package was unavailable or failed the security check.",
  @"alert.uptodate.title": @"Installer is up to date",
  @"alert.uptodate.body": @"No newer published macOS version is available.",
  @"btn.close": @"Close",
  @"alert.running.title": @"Update in progress",
  @"alert.running.body": @"Cancel it first with the Cancel the update button.",
 },
 @"fr": @{
  @"app.title": @"Sku Installer & Updater",
  @"role.heading": @"Titre",
  @"status.checking": @"Vérification de l'état.",
  @"games.acc": @"Version de WoW installée",
  @"path.none": @"Aucun dossier AddOns sélectionné pour le moment.",
  @"pack.de": @"Allemand", @"pack.fastde": @"Allemand rapide", @"pack.en": @"Anglais",
  @"pack.acc": @"Pack vocal",
  @"label.uilang": @"Langue de l'interface",
  @"login.title": @"Installer et mettre à jour l'outil de connexion WoW pour Hammerspoon",
  @"managed.fmt": @"Gérer %@ – disponible %@",
  @"name.pawn": @"Pawn comparaison d'équipement",
  @"name.gtfo": @"GTFO alerte de danger",
  @"name.bugsack": @"BugSack et BugGrabber",
  @"help.questie": @"Installe et met à jour la version Anniversary de Questie via CurseForge.",
  @"help.atlas": @"Installe et met à jour AtlasLootClassic via CurseForge ; la même version couvre Anniversary et Classic Era.",
  @"help.details": @"Installe et met à jour Details Damage Meter via CurseForge ; la même version couvre Anniversary et Classic Era.",
  @"help.pawn": @"Installe et met à jour Pawn via GitHub ; chaque client reçoit la version adaptée. Désélectionné par défaut.",
  @"help.dbm": @"Installe et met à jour DBM via GitHub ; chaque client reçoit les modules de raids et de donjons adaptés.",
  @"help.gtfo": @"Installe et met à jour GTFO, l'alerte sonore des effets au sol, via CurseForge.",
  @"help.bugsack": @"Installe et met à jour la capture d'erreurs BugSack avec BugGrabber via GitHub et CurseForge.",
  @"btn.update": @"Installer ou mettre à jour Sku et les AddOns sélectionnés",
  @"btn.repair": @"Réparer complètement l'installation",
  @"btn.cancel": @"Annuler la mise à jour",
  @"btn.inventory": @"Afficher les AddOns installés",
  @"help.inventory": @"Crée un aperçu en lecture seule, trié par ordre alphabétique, de tous les paquets d'AddOns détectés, avec versions et sources.",
  @"btn.browse": @"Choisir le dossier AddOns manuellement",
  @"btn.logs": @"Créer un paquet de diagnostic",
  @"btn.check": @"Rechercher une mise à jour de l'installateur",
  @"btn.quit": @"Quitter",
  @"acc.progress": @"Progression",
  @"output.ready": @"Prêt.",
  @"acc.output": @"Détails de l'installation",
  @"label.wow": @"Version de WoW",
  @"label.pack": @"Pack vocal",
  @"label.managed": @"AddOns gérés pour Anniversary et Classic Era",
  @"label.details": @"Détails",
  @"flavor.manual": @"Dossier AddOns manuel",
  @"suffix.sku": @" – Sku installé",
  @"help.managed.on": @"Les AddOns sélectionnés sont mis à jour avec Sku ; chaque client reçoit la version qui lui correspond.",
  @"help.managed.off": @"La gestion supplémentaire des AddOns est disponible pour Anniversary et Classic Era.",
  @"summary.uptodate": @"Tous les AddOns sont à jour.",
  @"summary.one": @"Une mise à jour est disponible pour %@.",
  @"summary.many": @"Des mises à jour sont disponibles pour %@.",
  @"word.and": @"et",
  @"word.dot": @" point ",
  @"word.new": @"nouvelle",
  @"status.refresh": @"Vérification de l'état de mise à jour de tous les AddOns sélectionnés.",
  @"panel.title": @"Choisir le dossier AddOns",
  @"panel.msg": @"Choisissez le dossier de version de WoW ou Interface/AddOns.",
  @"panel.prompt": @"Sélectionner",
  @"alert.invalidfolder.title": @"Dossier invalide",
  @"alert.invalidfolder.body": @"Veuillez choisir un dossier de version de WoW ou Interface/AddOns.",
  @"alert.folderunusable": @"Dossier inutilisable",
  @"busy.start": @"Démarrage de l'opération …\n",
  @"alert.startfailed": @"L'opération n'a pas pu être démarrée",
  @"status.repairing": @"Réparation complète en cours. Veuillez patienter.",
  @"status.updating": @"Sku et les AddOns sélectionnés sont en cours de mise à jour. Veuillez patienter.",
  @"alert.done.title": @"Mise à jour terminée",
  @"alert.fail.title": @"Échec de la mise à jour",
  @"alert.done.repair": @"Sku et tous les AddOns sélectionnés ont été entièrement réinstallés.",
  @"alert.done.update": @"Sku et les AddOns Anniversary sélectionnés ont été installés ou mis à jour avec succès.",
  @"alert.fail.body": @"Les versions précédentes ont été restaurées après une erreur de remplacement. Créez un paquet de diagnostic si nécessaire.",
  @"status.canceling": @"Annulation de la mise à jour.",
  @"status.inventory": @"Recensement des AddOns installés.",
  @"inv.none": @"Aucun AddOn n'a été détecté.",
  @"acc.inventory": @"AddOns installés",
  @"status.inv.done": @"La liste des AddOns a été créée.",
  @"status.inv.fail": @"La liste des AddOns n'a pas pu être créée.",
  @"alert.logs.done": @"Paquet de diagnostic créé",
  @"alert.logs.path": @"Le fichier ZIP se trouve ici :\n%@",
  @"alert.logs.fail.title": @"Échec du diagnostic",
  @"alert.logs.fail.body": @"Le paquet n'a pas pu être créé.",
  @"alert.check.fail.title": @"Échec de la vérification",
  @"alert.check.fail.body": @"La version de l'installateur n'a pas pu être vérifiée pour le moment.",
  @"alert.selfupdate.title": @"Nouvelle version de l'installateur disponible",
  @"alert.selfupdate.body": @"La version %@ peut être téléchargée depuis le dépôt officiel, vérifiée par SHA-256 et signature Developer ID, puis installée.",
  @"btn.updatenow": @"Mettre à jour maintenant",
  @"btn.later": @"Plus tard",
  @"alert.selfupdate.fail.title": @"Échec de la mise à jour de l'installateur",
  @"alert.selfupdate.fail.body": @"L'application existante n'a pas été remplacée. Le paquet téléchargé était indisponible ou n'a pas passé le contrôle de sécurité.",
  @"alert.uptodate.title": @"L'installateur est à jour",
  @"alert.uptodate.body": @"Aucune version macOS publiée plus récente n'est disponible.",
  @"btn.close": @"Fermer",
  @"alert.running.title": @"Mise à jour en cours",
  @"alert.running.body": @"Annulez-la d'abord avec le bouton Annuler la mise à jour.",
 }};
 });
 return t;
}
static NSString *L(NSString *key) { NSString *s = LocTables()[UILang][key]; if (!s) s = LocTables()[@"en"][key]; return s ?: key; }

/* The voice-pack popup shows localized names but the STORED value stays the
   canonical German title, for compatibility with existing preferences and the
   backend script's LanguagePack handling. */
static NSArray<NSString*> *CanonicalPacks(void) { return @[@"Deutsch", @"Deutsch schnell", @"Englisch"]; }
static NSArray<NSString*> *UILangCodes(void) { return @[@"de", @"en", @"fr"]; }

@interface SkuDelegate:NSObject<NSApplicationDelegate,NSWindowDelegate>
@property NSWindow *window; @property NSTextField *status,*path,*output; @property NSPopUpButton *games,*languages,*uiLangs;
@property NSButton *login,*questie,*atlas,*details,*pawn,*dbm,*gtfo,*bugsack,*update,*repair,*inventory,*cancel,*browseBtn,*logsBtn,*checkBtn,*quitBtn; @property NSProgressIndicator *progress;
@property NSTextField *heading,*wowLabel,*packLabel,*uiLangLabel,*managedLabel,*detailsLabel;
@property NSMutableArray<NSString*> *paths; @property NSUserDefaults *prefs; @property NSTask *task; @property NSPipe *pipe;
@property NSDictionary *latestCurated;
@end

@implementation SkuDelegate
- (NSTextField*)label:(NSString*)s size:(CGFloat)n bold:(BOOL)b { NSTextField*v=[NSTextField wrappingLabelWithString:s]; v.font=b?[NSFont boldSystemFontOfSize:n]:[NSFont systemFontOfSize:n]; v.accessibilityLabel=s; return v; }
- (NSButton*)button:(NSString*)s action:(SEL)a { NSButton*b=[NSButton buttonWithTitle:s target:self action:a]; b.accessibilityLabel=s; return b; }
- (void)initUILanguage { NSString*stored=[self.prefs stringForKey:@"UILanguage"]; if([UILangCodes() containsObject:stored?:@""]){UILang=stored;return;} NSString*first=NSLocale.preferredLanguages.firstObject?:@"en";NSString*sys=first.length>=2?[[first lowercaseString] substringToIndex:2]:@"en"; UILang=[UILangCodes() containsObject:sys]?sys:@"en"; [self.prefs setObject:UILang forKey:@"UILanguage"]; [self.prefs synchronize]; }
- (void)applicationDidFinishLaunching:(NSNotification*)n { [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; self.prefs=[[NSUserDefaults alloc]initWithSuiteName:@"org.sku-project.installer"]; [self initUILanguage]; self.paths=[NSMutableArray array]; [self buildWindow]; [self relabel]; self.output.stringValue=L(@"output.ready"); [self loadConfiguration]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; [self refreshStatus:YES]; [self checkInstallerAutomatically]; }
- (void)buildWindow {
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,780,920) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; self.window.delegate=self; self.window.minSize=NSMakeSize(720,840); [self.window center];
 self.heading=[self label:@"" size:24 bold:YES];
 self.status=[self label:@"" size:15 bold:NO]; self.status.accessibilityRoleDescription=@"Status";
 self.games=[NSPopUpButton new]; self.games.target=self; self.games.action=@selector(gameChanged:);
 self.path=[self label:@"" size:11 bold:NO]; self.path.textColor=NSColor.secondaryLabelColor;
 self.languages=[NSPopUpButton new]; self.languages.target=self; self.languages.action=@selector(changed:);
 self.uiLangs=[NSPopUpButton new]; [self.uiLangs addItemsWithTitles:@[@"Deutsch",@"English",@"Français"]]; self.uiLangs.target=self; self.uiLangs.action=@selector(uiLangChanged:);
 self.login=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.questie=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.atlas=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.details=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.pawn=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.dbm=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.gtfo=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.bugsack=[NSButton checkboxWithTitle:@"" target:self action:@selector(changed:)];
 self.update=[self button:@"" action:@selector(updateSku:)]; self.update.keyEquivalent=@"\r";
 self.repair=[self button:@"" action:@selector(repairSku:)]; self.cancel=[self button:@"" action:@selector(cancelTask:)]; self.cancel.hidden=YES;
 self.inventory=[self button:@"" action:@selector(showInventory:)];
 self.browseBtn=[self button:@"" action:@selector(browse:)]; self.logsBtn=[self button:@"" action:@selector(logs:)]; self.checkBtn=[self button:@"" action:@selector(checkApp:)]; self.quitBtn=[self button:@"" action:@selector(quit:)];
 self.progress=[NSProgressIndicator new]; self.progress.style=NSProgressIndicatorStyleBar; self.progress.indeterminate=YES; self.progress.hidden=YES;
 self.output=[NSTextField new]; self.output.editable=NO; self.output.selectable=YES; self.output.bezeled=YES; self.output.drawsBackground=YES; self.output.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
 self.wowLabel=[self label:@"" size:13 bold:YES]; self.packLabel=[self label:@"" size:13 bold:YES]; self.uiLangLabel=[self label:@"" size:13 bold:YES]; self.managedLabel=[self label:@"" size:13 bold:YES]; self.detailsLabel=[self label:@"" size:13 bold:YES];
 NSStackView*a=[NSStackView stackViewWithViews:@[self.update,self.repair,self.cancel]]; a.orientation=NSUserInterfaceLayoutOrientationHorizontal; a.spacing=8;
 NSStackView*t=[NSStackView stackViewWithViews:@[self.inventory,self.browseBtn,self.logsBtn,self.checkBtn,self.quitBtn]]; t.orientation=NSUserInterfaceLayoutOrientationHorizontal; t.spacing=8;
 NSStackView*managed=[NSStackView stackViewWithViews:@[self.questie,self.atlas,self.details,self.dbm,self.gtfo,self.bugsack,self.pawn]]; managed.orientation=NSUserInterfaceLayoutOrientationVertical; managed.alignment=NSLayoutAttributeLeading; managed.spacing=5;
 NSStackView*s=[NSStackView stackViewWithViews:@[self.heading,self.status,self.wowLabel,self.games,self.path,self.packLabel,self.languages,self.uiLangLabel,self.uiLangs,self.login,self.managedLabel,managed,a,self.progress,self.detailsLabel,self.output,t]]; s.orientation=NSUserInterfaceLayoutOrientationVertical; s.alignment=NSLayoutAttributeLeading; s.spacing=9; s.edgeInsets=NSEdgeInsetsMake(20,24,20,24); s.translatesAutoresizingMaskIntoConstraints=NO; [self.window.contentView addSubview:s];
 [NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],[s.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],[s.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor],[self.status.widthAnchor constraintEqualToAnchor:s.widthAnchor constant:-48],[self.games.widthAnchor constraintEqualToAnchor:s.widthAnchor constant:-48],[self.path.widthAnchor constraintEqualToAnchor:s.widthAnchor constant:-48],[self.progress.widthAnchor constraintEqualToAnchor:s.widthAnchor constant:-48],[self.output.widthAnchor constraintEqualToAnchor:s.widthAnchor constant:-48],[self.output.heightAnchor constraintGreaterThanOrEqualToConstant:105]]];
}
/* Applies every static localized string; called once after buildWindow and
   again whenever the interface language changes, so the switch is live. */
- (void)setLabel:(NSTextField*)f text:(NSString*)text { f.stringValue=text; f.accessibilityLabel=text; }
- (void)setButton:(NSButton*)b title:(NSString*)title { b.title=title; b.accessibilityLabel=title; }
- (void)relabel {
 self.window.title=L(@"app.title");
 [self setLabel:self.heading text:L(@"app.title")]; self.heading.accessibilityRoleDescription=L(@"role.heading");
 self.games.accessibilityLabel=L(@"games.acc");
 NSInteger packIndex=self.languages.numberOfItems?self.languages.indexOfSelectedItem:0;
 [self.languages removeAllItems]; [self.languages addItemsWithTitles:@[L(@"pack.de"),L(@"pack.fastde"),L(@"pack.en")]]; if(packIndex>=0&&packIndex<3)[self.languages selectItemAtIndex:packIndex];
 self.languages.accessibilityLabel=L(@"pack.acc");
 [self.uiLangs selectItemAtIndex:[UILangCodes() indexOfObject:UILang]]; self.uiLangs.accessibilityLabel=L(@"label.uilang");
 [self setButton:self.login title:L(@"login.title")];
 self.questie.accessibilityHelp=L(@"help.questie"); self.atlas.accessibilityHelp=L(@"help.atlas"); self.details.accessibilityHelp=L(@"help.details"); self.pawn.accessibilityHelp=L(@"help.pawn"); self.dbm.accessibilityHelp=L(@"help.dbm"); self.gtfo.accessibilityHelp=L(@"help.gtfo"); self.bugsack.accessibilityHelp=L(@"help.bugsack");
 [self setButton:self.update title:L(@"btn.update")]; [self setButton:self.repair title:L(@"btn.repair")]; [self setButton:self.cancel title:L(@"btn.cancel")];
 [self setButton:self.inventory title:L(@"btn.inventory")]; self.inventory.accessibilityHelp=L(@"help.inventory");
 [self setButton:self.browseBtn title:L(@"btn.browse")]; [self setButton:self.logsBtn title:L(@"btn.logs")]; [self setButton:self.checkBtn title:L(@"btn.check")]; [self setButton:self.quitBtn title:L(@"btn.quit")];
 self.progress.accessibilityLabel=L(@"acc.progress");
 self.output.accessibilityLabel=L(@"acc.output");
 [self setLabel:self.wowLabel text:L(@"label.wow")]; [self setLabel:self.packLabel text:L(@"label.pack")]; [self setLabel:self.uiLangLabel text:L(@"label.uilang")]; [self setLabel:self.managedLabel text:L(@"label.managed")]; [self setLabel:self.detailsLabel text:L(@"label.details")];
 [self applyLatestCuratedLabels]; [self updatePath];
}
- (NSArray*)detected { NSString*h=NSHomeDirectory(); NSArray*r=@[@"/Applications/World of Warcraft",[h stringByAppendingPathComponent:@"Applications/World of Warcraft"]],*f=@[@"_anniversary_",@"_classic_era_",@"_classic_",@"_retail_"]; NSMutableArray*x=[NSMutableArray array]; for(NSString*root in r)for(NSString*fl in f){NSString*p=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/Interface/AddOns",fl]]; BOOL d=NO;if([[NSFileManager defaultManager]fileExistsAtPath:p isDirectory:&d]&&d)[x addObject:p];}return x; }
- (NSString*)flavor:(NSString*)p { if([p containsString:@"/_anniversary_/"])return @"Anniversary";if([p containsString:@"/_classic_era_/"])return @"Classic Era";if([p containsString:@"/_classic_/"])return @"Classic";if([p containsString:@"/_retail_/"])return @"Retail";return L(@"flavor.manual"); }
- (NSString*)selected { NSInteger i=self.games.indexOfSelectedItem; return i>=0&&i<(NSInteger)self.paths.count?self.paths[i]:nil; }
- (void)reload:(NSString*)selected { [self.games removeAllItems];for(NSString*p in self.paths){BOOL sku=[[NSFileManager defaultManager]fileExistsAtPath:[p stringByAppendingPathComponent:@"Sku"]];[self.games addItemWithTitle:[NSString stringWithFormat:@"%@%@",[self flavor:p],sku?L(@"suffix.sku"):@""]];}NSUInteger i=[self.paths indexOfObject:selected];if(i!=NSNotFound)[self.games selectItemAtIndex:i];else if(self.paths.count)[self.games selectItemAtIndex:0];[self updatePath]; }
- (NSControlStateValue)managedState:(NSString*)key { NSString*v=[self.prefs stringForKey:key];if(!v.length)return [key isEqualToString:@"ManagePawn"]?NSControlStateValueOff:NSControlStateValueOn;return[v isEqualToString:@"Nein"]?NSControlStateValueOff:NSControlStateValueOn; }
- (void)loadConfiguration { [self.paths addObjectsFromArray:self.detected];NSString*p=[self.prefs stringForKey:@"SelectedAddonsFolder"]?:@"";if(p.length&&![self.paths containsObject:p])[self.paths addObject:p];[self reload:p];NSUInteger packIndex=[CanonicalPacks() indexOfObject:[self.prefs stringForKey:@"LanguagePack"]?:@"Deutsch"];[self.languages selectItemAtIndex:packIndex==NSNotFound?0:(NSInteger)packIndex];self.login.state=[[self.prefs stringForKey:@"LoginTool"]isEqualToString:@"Ja"]?NSControlStateValueOn:NSControlStateValueOff;self.questie.state=[self managedState:@"ManageQuestie"];self.atlas.state=[self managedState:@"ManageAtlasLoot"];self.details.state=[self managedState:@"ManageDetails"];self.pawn.state=[self managedState:@"ManagePawn"];self.dbm.state=[self managedState:@"ManageDBM"];self.gtfo.state=[self managedState:@"ManageGTFO"];self.bugsack.state=[self managedState:@"ManageBugSack"];[self updateManagedAvailability];[self save]; }
- (void)saveManaged:(NSButton*)button key:(NSString*)key { [self.prefs setObject:button.state==NSControlStateValueOn?@"Ja":@"Nein" forKey:key]; }
- (void)save { if(self.selected)[self.prefs setObject:self.selected forKey:@"SelectedAddonsFolder"];NSInteger packIndex=self.languages.indexOfSelectedItem;[self.prefs setObject:(packIndex>=0&&packIndex<3?CanonicalPacks()[packIndex]:@"Deutsch") forKey:@"LanguagePack"];[self.prefs setObject:self.login.state==NSControlStateValueOn?@"Ja":@"Nein" forKey:@"LoginTool"];[self.prefs setObject:UILang forKey:@"UILanguage"];[self saveManaged:self.questie key:@"ManageQuestie"];[self saveManaged:self.atlas key:@"ManageAtlasLoot"];[self saveManaged:self.details key:@"ManageDetails"];[self saveManaged:self.pawn key:@"ManagePawn"];[self saveManaged:self.dbm key:@"ManageDBM"];[self saveManaged:self.gtfo key:@"ManageGTFO"];[self saveManaged:self.bugsack key:@"ManageBugSack"];[self.prefs synchronize]; }
- (BOOL)managedClientSelected { return [self.selected containsString:@"/_anniversary_/"]||[self.selected containsString:@"/_classic_era_/"]; }
- (void)updateManagedAvailability { BOOL managed=[self managedClientSelected];for(NSButton*b in @[self.questie,self.atlas,self.details,self.dbm,self.gtfo,self.bugsack,self.pawn]){b.enabled=managed;b.accessibilityEnabled=managed;}NSString*help=managed?L(@"help.managed.on"):L(@"help.managed.off");for(NSButton*b in @[self.questie,self.atlas,self.details,self.dbm,self.gtfo,self.bugsack,self.pawn])b.accessibilityHelp=help; }
- (void)updatePath { self.path.stringValue=self.selected?:L(@"path.none");self.path.accessibilityLabel=self.path.stringValue;[self updateManagedAvailability]; }
- (NSString*)installed { NSString*t=[self.selected stringByAppendingPathComponent:@"Sku/Sku.toc"];NSString*x=t?[NSString stringWithContentsOfFile:t encoding:NSUTF8StringEncoding error:nil]:nil;NSRegularExpression*r=[NSRegularExpression regularExpressionWithPattern:@"(?im)^##\\s*Version:\\s*([^\\r\\n]+)" options:0 error:nil];NSTextCheckingResult*m=[r firstMatchInString:x?:@"" options:0 range:NSMakeRange(0,x.length)];return m?[[x substringWithRange:[m rangeAtIndex:1]]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil; }
- (NSDictionary*)addonManifest { NSString*p=[self.selected stringByAppendingPathComponent:@"SkuInstall.json"];NSData*d=p?[NSData dataWithContentsOfFile:p]:nil;if(!d)return @{};NSDictionary*j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];NSDictionary*a=[j isKindOfClass:NSDictionary.class]?j[@"addons"]:nil;return[a isKindOfClass:NSDictionary.class]?a:@{}; }
- (BOOL)managedAddonCurrent:(NSDictionary*)manifest key:(NSString*)key version:(NSString*)version roots:(NSArray*)roots { if(![manifest[key] isEqualToString:version])return NO;for(NSString*r in roots)if(![[NSFileManager defaultManager]fileExistsAtPath:[self.selected stringByAppendingPathComponent:r]])return NO;return YES; }
- (NSString*)latestFor:(NSString*)key fallback:(NSString*)fallback { id entry=self.latestCurated[key];id value=[entry isKindOfClass:NSDictionary.class]?entry[@"latest"]:nil;return[value isKindOfClass:NSString.class]&&[value length]?value:fallback; }
- (void)applyLatestCuratedLabels { NSString*fmt=L(@"managed.fmt");[self setButton:self.questie title:[NSString stringWithFormat:fmt,@"Questie",[self latestFor:@"Questie" fallback:@"11.37.1"]]];[self setButton:self.atlas title:[NSString stringWithFormat:fmt,@"AtlasLootClassic",[self latestFor:@"AtlasLoot" fallback:@"2.5.6.12334"]]];[self setButton:self.details title:[NSString stringWithFormat:fmt,@"Details Damage Meter",[self latestFor:@"Details" fallback:@"20260811.15275.172"]]];[self setButton:self.dbm title:[NSString stringWithFormat:fmt,@"Deadly Boss Mods",[self latestFor:@"DBM" fallback:@"12.1.8"]]];[self setButton:self.gtfo title:[NSString stringWithFormat:fmt,L(@"name.gtfo"),[self latestFor:@"GTFO" fallback:@"6.9.1"]]];[self setButton:self.bugsack title:[NSString stringWithFormat:fmt,L(@"name.bugsack"),[self latestFor:@"BugSack" fallback:@"12.0.13"]]];[self setButton:self.pawn title:[NSString stringWithFormat:fmt,L(@"name.pawn"),[self latestFor:@"Pawn" fallback:@"2.13.15"]]]; }
- (NSArray*)curatedUpdates { if(![self managedClientSelected])return @[];BOOL era=[self.selected containsString:@"/_classic_era_/"];NSDictionary*m=self.addonManifest;NSMutableArray*u=[NSMutableArray array];if(self.questie.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:@"CurseQuestie" version:[self latestFor:@"Questie" fallback:@"11.37.1"] roots:@[@"Questie"]])[u addObject:@"Questie"];if(self.atlas.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:@"CurseAtlasLootAnniversary" version:[self latestFor:@"AtlasLoot" fallback:@"2.5.6.12334"] roots:@[@"AtlasLootClassic",@"AtlasLootClassic_Data"]])[u addObject:@"AtlasLootClassic"];if(self.details.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:@"CurseDetails" version:[self latestFor:@"Details" fallback:@"20260811.15275.172"] roots:@[@"Details",@"Details_DataStorage"]])[u addObject:@"Details Damage Meter"];if(self.pawn.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:(era?@"CursePawnVanilla":@"CursePawnTBC") version:[self latestFor:@"Pawn" fallback:@"2.13.15"] roots:@[@"Pawn"]])[u addObject:@"Pawn"];if(self.dbm.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:@"DBMCore" version:[self latestFor:@"DBM" fallback:@"12.1.8"] roots:(era?@[@"DBM-Core",@"DBM-Raids-Vanilla",@"DBM-Party-Vanilla"]:@[@"DBM-Core",@"DBM-Raids-BC",@"DBM-Party-BC"])])[u addObject:@"Deadly Boss Mods"];if(self.gtfo.state==NSControlStateValueOn&&![self managedAddonCurrent:m key:@"CurseGTFO" version:[self latestFor:@"GTFO" fallback:@"6.9.1"] roots:@[@"GTFO"]])[u addObject:@"GTFO"];if(self.bugsack.state==NSControlStateValueOn&&(![self managedAddonCurrent:m key:@"BugSack" version:[self latestFor:@"BugSack" fallback:@"12.0.13"] roots:@[@"BugSack"]]||![self managedAddonCurrent:m key:@"CurseBugGrabber" version:@"12.0.21" roots:@[@"!BugGrabber"]]))[u addObject:L(@"name.bugsack")];return u; }
- (NSString*)updateSummaryWithLatestSku:(NSString*)latest { NSMutableArray*u=[NSMutableArray array];NSString*have=self.installed;if(!have||![have isEqualToString:latest])[u addObject:@"Sku"];[u addObjectsFromArray:self.curatedUpdates];if(!u.count)return L(@"summary.uptodate");NSString*names=u.count==1?u.firstObject:[[u subarrayWithRange:NSMakeRange(0,u.count-1)]componentsJoinedByString:@", "];if(u.count>1)names=[NSString stringWithFormat:@"%@ %@ %@",names,L(@"word.and"),u.lastObject];return u.count==1?[NSString stringWithFormat:L(@"summary.one"),names]:[NSString stringWithFormat:L(@"summary.many"),names]; }
- (NSString*)spoken:(NSString*)v{return[v stringByReplacingOccurrencesOfString:@"." withString:L(@"word.dot")];}
- (void)setStatus:(NSString*)s announce:(BOOL)a { self.status.stringValue=s;self.status.accessibilityLabel=s;if(a)NSAccessibilityPostNotificationWithUserInfo(self.status,NSAccessibilityAnnouncementRequestedNotification,@{NSAccessibilityAnnouncementKey:s,NSAccessibilityPriorityKey:@(NSAccessibilityPriorityHigh)}); }
- (void)refreshCuratedWithLatestSku:(NSString*)latest announce:(BOOL)announce { NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];t.arguments=@[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"SkuInstaller.command"],@"--addon-update-status"];NSPipe*p=[NSPipe pipe];t.standardOutput=p;t.standardError=[NSFileHandle fileHandleWithNullDevice];t.terminationHandler=^(NSTask*finished){NSData*d=[p.fileHandleForReading readDataToEndOfFile];NSDictionary*j=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;dispatch_async(dispatch_get_main_queue(),^{if([j isKindOfClass:NSDictionary.class])self.latestCurated=j;[self applyLatestCuratedLabels];[self setStatus:[self updateSummaryWithLatestSku:latest] announce:announce];[self reload:self.selected];});};if(![t launchAndReturnError:nil]){[self setStatus:[self updateSummaryWithLatestSku:latest] announce:announce];} }
/* Version detection resolves the releases/latest redirect and reads the tag —
   the same mechanism the Windows installer uses (GitHubClient.cs). Never scrape
   the website HTML for a version string. */
- (void)refreshStatus:(BOOL)announce { [self setStatus:L(@"status.refresh") announce:NO];NSMutableURLRequest*q=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://github.com/Sku75/Sku-WoW-Addon-TBC/releases/latest"]];q.HTTPMethod=@"HEAD";[[[NSURLSession sharedSession]dataTaskWithRequest:q completionHandler:^(NSData*d,NSURLResponse*r,NSError*e){NSString*tag=r.URL.lastPathComponent?:@"";if([tag hasPrefix:@"v"])tag=[tag substringFromIndex:1];NSRegularExpression*rx=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(\\.[0-9]+)+$" options:0 error:nil];NSString*l=[rx firstMatchInString:tag options:0 range:NSMakeRange(0,tag.length)]?tag:@"43.3";dispatch_async(dispatch_get_main_queue(),^{[self refreshCuratedWithLatestSku:l announce:announce];});}]resume]; }
- (void)gameChanged:(id)x{[self updatePath];[self save];[self refreshStatus:YES];}- (void)changed:(id)x{[self save];[self refreshStatus:YES];}
- (void)uiLangChanged:(id)x{NSInteger i=self.uiLangs.indexOfSelectedItem;if(i>=0&&i<3)UILang=UILangCodes()[i];[self save];[self relabel];[self reload:self.selected];[self refreshStatus:YES];}
- (NSString*)normalize:(NSString*)p { p=p.stringByStandardizingPath;if([p.lastPathComponent isEqualToString:@"AddOns"]&&[p.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Interface"])return p;if([p.lastPathComponent isEqualToString:@"Interface"])return[p stringByAppendingPathComponent:@"AddOns"];NSString*c=[p stringByAppendingPathComponent:@"Interface/AddOns"];return[[NSFileManager defaultManager]fileExistsAtPath:c]?c:nil; }
- (void)browse:(id)x { NSOpenPanel*p=NSOpenPanel.openPanel;p.title=L(@"panel.title");p.message=L(@"panel.msg");p.prompt=L(@"panel.prompt");p.canChooseDirectories=YES;p.canChooseFiles=NO;if([p runModal]!=NSModalResponseOK)return;NSString*q=[self normalize:p.URL.path];if(!q){[self alert:L(@"alert.invalidfolder.title") info:L(@"alert.invalidfolder.body")];return;}NSError*e;[[NSFileManager defaultManager]createDirectoryAtPath:q withIntermediateDirectories:YES attributes:nil error:&e];if(e){[self alert:L(@"alert.folderunusable") info:e.localizedDescription];return;}if(![self.paths containsObject:q])[self.paths addObject:q];[self reload:q];[self save];[self refreshStatus:YES]; }
- (void)busy:(BOOL)b { self.update.enabled=!b;self.repair.enabled=!b;self.inventory.enabled=!b;self.games.enabled=!b;self.languages.enabled=!b;self.uiLangs.enabled=!b;self.login.enabled=!b;self.cancel.hidden=!b;self.progress.hidden=!b;if(b){for(NSButton*m in @[self.questie,self.atlas,self.details,self.dbm,self.gtfo,self.bugsack,self.pawn])m.enabled=NO;}else [self updateManagedAvailability];b?[self.progress startAnimation:nil]:[self.progress stopAnimation:nil]; }
- (void)backend:(NSString*)arg done:(void(^)(int,NSString*))done {
 [self save]; [self busy:YES]; self.output.stringValue=L(@"busy.start");
 self.task=[NSTask new]; self.task.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];
 self.task.arguments=@[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"SkuInstaller.command"],arg];
 NSMutableDictionary*env=[NSProcessInfo.processInfo.environment mutableCopy]; env[@"SKU_UI_LANGUAGE"]=UILang; self.task.environment=env;
 self.pipe=[NSPipe pipe]; self.task.standardOutput=self.pipe; self.task.standardError=self.pipe;
 NSMutableData*all=[NSMutableData data]; __weak typeof(self) weakSelf=self;
 self.pipe.fileHandleForReading.readabilityHandler=^(NSFileHandle*h){
  NSData*d=h.availableData; if(!d.length)return; @synchronized(all){[all appendData:d];}
  NSString*s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];
  dispatch_async(dispatch_get_main_queue(),^{typeof(self) self=weakSelf;if(self&&s.length)self.output.stringValue=[self.output.stringValue stringByAppendingString:s];});
 };
 self.task.terminationHandler=^(NSTask*t){
  typeof(self) self=weakSelf;if(!self)return; self.pipe.fileHandleForReading.readabilityHandler=nil;
  NSString*s; @synchronized(all){s=[[NSString alloc]initWithData:all encoding:NSUTF8StringEncoding]?:@"";}
  dispatch_async(dispatch_get_main_queue(),^{typeof(self) self=weakSelf;if(!self)return;[self busy:NO];self.task=nil;done(t.terminationStatus,s);});
 };
 NSError*e;if(![self.task launchAndReturnError:&e]){[self busy:NO];self.task=nil;[self alert:L(@"alert.startfailed") info:e.localizedDescription];}
}
- (void)install:(BOOL)repair { if(!self.selected){[self browse:nil];if(!self.selected)return;}[self setStatus:repair?L(@"status.repairing"):L(@"status.updating") announce:YES];[self backend:repair?@"--headless-update-force":@"--headless-update" done:^(int c,NSString*s){[self alert:c==0?L(@"alert.done.title"):L(@"alert.fail.title") info:c==0?(repair?L(@"alert.done.repair"):L(@"alert.done.update")):L(@"alert.fail.body")];[self refreshStatus:YES];}]; }
- (void)updateSku:(id)x{[self install:NO];}- (void)repairSku:(id)x{[self install:YES];}- (void)cancelTask:(id)x{if(self.task.running){[self.task interrupt];[self setStatus:L(@"status.canceling") announce:YES];}}
- (void)showInventory:(id)x{if(!self.selected){[self browse:nil];if(!self.selected)return;}[self setStatus:L(@"status.inventory") announce:YES];[self backend:@"--addon-inventory" done:^(int c,NSString*s){NSString*result=[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];self.output.stringValue=result.length?result:L(@"inv.none");self.output.accessibilityLabel=L(@"acc.inventory");[self setStatus:c==0?L(@"status.inv.done"):L(@"status.inv.fail") announce:YES];}];}
- (void)logs:(id)x{[self backend:@"--collect-logs" done:^(int c,NSString*s){[self alert:c==0?L(@"alert.logs.done"):L(@"alert.logs.fail.title") info:c==0?[NSString stringWithFormat:L(@"alert.logs.path"),[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]:L(@"alert.logs.fail.body")];}];}
- (void)checkApp:(id)x{[self backend:@"--self-update-check" done:^(int c,NSString*s){if(c!=0){[self alert:L(@"alert.check.fail.title") info:L(@"alert.check.fail.body")];return;}if([s containsString:@"AVAILABLE=1"]){NSRegularExpression*r=[NSRegularExpression regularExpressionWithPattern:@"LATEST=([^\\r\\n]+)" options:0 error:nil];NSTextCheckingResult*m=[r firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];NSString*v=m?[s substringWithRange:[m rangeAtIndex:1]]:L(@"word.new");NSAlert*a=[NSAlert new];a.messageText=L(@"alert.selfupdate.title");a.informativeText=[NSString stringWithFormat:L(@"alert.selfupdate.body"),v];[a addButtonWithTitle:L(@"btn.updatenow")];[a addButtonWithTitle:L(@"btn.later")];if([a runModal]==NSAlertFirstButtonReturn){[self backend:@"--self-update" done:^(int code,NSString*out){if(code==0)[NSApp terminate:nil];else[self alert:L(@"alert.selfupdate.fail.title") info:L(@"alert.selfupdate.fail.body")];}];}}else[self alert:L(@"alert.uptodate.title") info:L(@"alert.uptodate.body")];}];}
- (void)checkInstallerAutomatically { NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];t.arguments=@[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"SkuInstaller.command"],@"--self-update-check"];NSPipe*p=[NSPipe pipe];t.standardOutput=p;t.standardError=[NSFileHandle fileHandleWithNullDevice];t.terminationHandler=^(NSTask*finished){NSData*d=[p.fileHandleForReading readDataToEndOfFile];NSString*s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"";if([s containsString:@"AVAILABLE=1"])dispatch_async(dispatch_get_main_queue(),^{[self checkApp:nil];});};[t launchAndReturnError:nil]; }
- (void)alert:(NSString*)t info:(NSString*)i{NSAlert*a=[NSAlert new];a.messageText=t;a.informativeText=i;[a addButtonWithTitle:L(@"btn.close")];[a runModal];}
- (void)quit:(id)x{if(!self.task.running)[NSApp terminate:nil];}- (BOOL)windowShouldClose:(NSWindow*)w{if(self.task.running){[self alert:L(@"alert.running.title") info:L(@"alert.running.body")];return NO;}return YES;}- (void)windowWillClose:(NSNotification*)n{[NSApp terminate:nil];}
@end
int main(int argc,const char*argv[]){@autoreleasepool{NSApplication*a=NSApplication.sharedApplication;SkuDelegate*d=[SkuDelegate new];a.delegate=d;[a run];}return 0;}
