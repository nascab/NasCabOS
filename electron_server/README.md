安装说明
目前better-sqlite3最高支持的版本是electron37
https://github.com/WiseLibs/better-sqlite3/releases?page=1

    安装better-sqlite3需要从用electron-rebuid来重新编译适应当前的electron版本
        node_modules/.bin/electron-rebuild -f -w better-sqlite3

    ELECTRON和nodejs版本对应关系 最好使用对应的nodejs开发版本
        https://www.electronjs.org/zh/docs/latest/tutorial/electron-timelines

引用的lib说明
portfinder: 用于查找可用端口
knex: 用于操作数据库
sharp: 用于图片处理
