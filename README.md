# NervTech Dedup utility

This utility can be used to look for duplicated files in a given folder, recursively. (Check the [NervDedup Project Webpage](http://wiki.nervtech.org/doku.php?id=public:projects:nerv_dedup:nerv_dedup) for more details).

## Usage

  * To use this tool on windows, a convinient **dedup.bat** file is included in the project, to find the duplicated files and folders starting from a given directory, one just need to navigate into that directory and then execute:
  
  ```
    dedup.bat
  ```

  * On the first pass, the tool will generate the MD5 hashes for all the files contained in the folder, which may take some time, but then this data is written into a local **dedup_data.lua** file, along with each file timestamp, so the next time file duplication is checked, the hashes are not recomputed for files that did not change.

  * Once the hashes for all the current files are available, the utility can check for duplicated hashes and report the list of duplicated files accordingly.

  * Note that this tool also support checking for duplicated folders: it will take the hashes for all the content of the folder of interest, combine them into a longer string and hash this again to get the folder hash, which is then compared to all the other hashes in the data table to detect potential duplication.

  * On completion, the list of duplicated files/folders are reported on the standard output and also written into a **dedup.log** file (in case any are found). And as a side bonus, this utility can also detect "empty folders" (eg. folders that do not contain any file, and in that sense, folders that contains only other empty folders are **also considered as empty**).

  * The NervDedup app will also read its desired configuration from the **dedup_config.lua**, which can provide a list of ignored patterns when searching for files and folders, and also specify if empty folders should be deleted directly instead of just reporting them when the process is completed.

## Changelog

### v1.0.0 - 05/03/2017

  * Initial release.

### v1.0.1 - 05/03/2017

  * Added C md5 implementation (with FFI access) providing a significant speed up of about 60x !

## License

  This code is released under the MIT license.
