# disco_interfaces

Perl program to discover the interfaces from the hosts stored in Centreon. You can choose the discovered interfaces
and the script create for you a CLAPI file (Centreon CLI for create object into Centreon).

  - INPUT : config file (disco_interfaces.cfg)
  - OUTPUT : CLAPI.sh (you can run to create the interfaces in Centreon.

![Screenshot 1](https://github.com/sgaudart/disco_interfaces/blob/master/disco_interfaces.png)

## Requirement

  - Perl (main script)
  - the script [pyselection.py] (https://github.com/sgaudart/pyselection) (python2.X & curses module)
  - IMPORTANT : you need to launch disco_interfaces.pl with the nagios/centreon user (need to access to the pollers with SSH).

## Usage

```erb
./disco_interfaces.pl
```

## Usefull Keys
  - UP/DOWN : navigate
  - SPACE : select/unselect the line
  - OTHER KEY : you can make a dynamic text filter
  - BACKSPACE : you delete one chr of the text filter
  - ENTER : save and exit
  - ESC : no save and exit
