<p align="center">
<img src="https://github.com/coldrockgames/god-gdgist-community/blob/ccf4463b456430992316b7ed6536587c184de2c5/assets/gdgist-logo-trans-256.png"/>
</p>

> [!NOTE]  
> This repository is under construction and currently being built up for the release of the plugin!

> [!NOTE]
> **Giving Back to the Engine:** As a passionate Godot developer, I am pledging **20% of all GDGist Pro net revenues** directly to the [Godot Development Fund](https://fund.godotengine.org/). By upgrading your IDE workflow, you are also actively supporting the future of the engine we all rely on.\
> *I am not affiliated in any way with the Godot Foundation. This is just my way to say "Thank you" to the makers of Godot!*


# GDGist Community Edition

![Godot Version](https://img.shields.io/badge/Godot-4.6+-blue.svg) ![License](https://img.shields.io/badge/License-MIT-green.svg) ![Version](https://img.shields.io/badge/GDGist_Version-2606.3-orange)

GDGist is a deeply integrated IDE Code Snippet Manager built specifically for the Godot Engine (version 4.6 and above). It is engineered for veteran developers to eliminate repetitive boilerplate code by providing robust, contextual workflow automation directly within the Godot editor. 

## Features (Community Edition)

The Community Edition provides a robust core engine for managing project-specific code:

* **Project-Local Management:** Snippets are securely stored in a hidden `.gdgist` directory at the project root, keeping your FileSystem clean and ensuring version control handles snippets organically.
* **Context-Aware Insertion:** Use the `Alt+.` shortcut to invoke an intelligent insertion menu. This system parses the current GDScript class inheritance to display only the code blocks relevant to your current context.
* **Custom Tree Dock Interface:** Organize snippets with full drag-and-drop support and syntax-highlighted tooltips for rapid visual scanning before insertion.

<img width="633" height="318" alt="image" src="https://github.com/user-attachments/assets/8cba80c7-17ac-41d4-a05c-95872db592f0" />

## Installation

1. Download the repository or install directly via the Godot AssetLib.
2. Extract the contents and ensure the `coldrock-gdgist` folder is placed in your project's `addons/` directory: `res://addons/coldrock-gdgist/`
3. Navigate to **Project > Project Settings > Plugins** in the Godot Editor.
4. Locate **GDGist** and check the **Enable** box.

## Automatic export exclusion
This plugin is not meant to run in an exported game, as it is an extension to the IDE of Godot. It will automatically register an `EditorExportPlugin`, which will prevent it from being part of your binary exports. 

## Quick Start Guide

1. **Accessing the UI:** Once enabled, the GDGist custom tree dock will appear in your editor's panel layout. 
2. **Creating Snippets:**\
  2a. Right-click within the dock to create new folders or snippets. You can paste your boilerplate code directly into the snippet definition.\
  2b. Alternatively, select any text block in your script and right click in the editor. The context menu will show you gist creation options at the bottom of the menu.
   
      <img width="499" height="183" alt="image" src="https://github.com/user-attachments/assets/b3f47e2c-6b65-4e52-9f91-122bc6ca7b03" />


4. **Inserting Snippets:** Navigate to any GDScript file. Place your cursor where the boilerplate is required and press `RAlt+.` to open the contextual insertion menu.
 
   <img width="469" height="229" alt="image" src="https://github.com/user-attachments/assets/45f2d87d-03c5-4108-b60e-8230d1172a2a" />


## Upgrading to Pro

For developers requiring advanced automation, a premium **Pro Edition** upgrade is available via [itch.io](https://coldrockgames.itch.io/gdgist).

The Pro Edition seamlessly unlocks the following features:

* **Global Gists:** Store cross-project snippets in your OS user data directory, making them instantly available across all your Godot projects without manual copying.

   <img width="375" height="331" alt="image" src="https://github.com/user-attachments/assets/0f05fadc-ceb1-4c5c-bef7-f4799c1c6927" />

* **Editor Scripts ("Warp Drive"):** Write and execute raw GDScript directly inside IDE memory. Automate repetitive tasks (e.g., node batch-renaming, sprite atlas splitting) without polluting your project's file system with temporary scripts.

   <img width="1064" height="722" alt="image" src="https://github.com/user-attachments/assets/2d1c2db0-c3e0-427a-8dfc-e08b9fc056e2" />

* **Interface Extractor:** A custom parser that scans your GDScript files for virtual/abstract methods (or custom `@virtual` annotations) and automatically converts them into ready-to-deploy snippet blocks.

   <img width="309" height="616" alt="image" src="https://github.com/user-attachments/assets/9c6ea7f0-6913-4366-b23f-e16fbf3344cc" />
