@echo off
:start
set /p CMD=shinoa@beyond-clouds ~/Desktop/TheFakeFiles/Projects/Irie $ 
if "%CMD%" EQU "quit" goto leave
%CMD%
goto start

:leave
pause