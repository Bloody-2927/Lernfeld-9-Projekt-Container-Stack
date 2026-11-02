@echo off
rem Verbindet die Netzlaufwerke des Uebungslabors (Pflichtenheft F-04).
rem Aufruf: map-shares.cmd 1   (Benutzer1)   oder   map-shares.cmd 2   (Benutzer2)
rem Windows erlaubt pro Server nur ein Konto gleichzeitig (Fehler 1219), deshalb eine Nummer waehlen.
rem Passwoerter werden abgefragt und stehen nicht im Skript.

set N=%1
if "%N%"=="" (
  echo Aufruf: %~nx0 1  oder  %~nx0 2
  exit /b 1
)
if not "%N%"=="1" if not "%N%"=="2" (
  echo Ungueltige Nummer "%N%". Erlaubt: 1 oder 2.
  exit /b 1
)

set SERVER=files.kopernikus-lab.lokal

rem Alte Verbindungen entfernen (gegen Fehler 1219)
net use * /delete /y >nul 2>&1

net use P: \\%SERVER%\pub /persistent:no
if errorlevel 1 (
  echo FEHLER: pub nicht erreichbar. Pruefen: Server %SERVER% erreichbar? Gastzugriff am Client erlaubt?
  exit /b 2
)

net use Q: \\%SERVER%\Benutzer%N% * /user:benutzer%N% /persistent:no
if errorlevel 1 (
  echo FEHLER: Anmeldung an Benutzer%N% fehlgeschlagen. Benutzername oder Passwort falsch?
  exit /b 3
)

echo Laufwerke verbunden: P: ^(pub, nur lesen^) und Q: ^(Benutzer%N%^).
