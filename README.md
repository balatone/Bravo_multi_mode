Bravo++
--

Bravo++ allows you to configure multi-mode functionality, so that you get more out of your Honeycomb Bravo than just the basic autopilot. The default mode (AUTO) will retain the standard autopilot functionality, but you can configure additional modes so that you can use the selector switch, buttons and rotating button to control other functionality in the aircraft. There are some configuration files provided for the default aircraft such as the Cessna 172, the King Air C90B, and the Cirrus SF50 along with configurations for the Aerobask DA42 and DA62. Hopefully these will be enough so that you can configure you're own aircraft and perhaps submit it to the collection.

The functionality is provided as a FlyWithLua script and consists of 3 parts:

- BravoMultiMode.lua - This is the main script that provides all the functionality and is placed in the FlyWithLua/Scripts directory.
- log.lua -  This is a log utility that is used by BravoMultiMode.lua and is located in the FlyWithLua/Modules directory.
- config file - This is where you onfigure all the different modes you want to have on your specific aricraft. Some example files are included in the FlyWithLua/conf directory and should be placed directly under the corresponding aircraft folder.

There is also an extra utility called ButtonLogUtility.lua that is used to determine which button the alt selector is mapped to in X-Plane. 

* Installation
You should begin by installing the [FlyWithLua](https://forums.x-plane.org/files/file/82888-flywithlua-ng-next-generation-plus-edition-for-x-plane-12-win-lin-mac/) plugin for X-PLane 12. If you already have it installed make sure that it is the NG version.

You can either download the zip file from the X-Plane forum or get them from the GitHub repository. All relevant files are found under the FlyWithLua directory and the entire directory should be copied to 