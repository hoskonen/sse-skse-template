-- include subprojects
includes("lib/commonlibsse-ng")

-- set project constants
set_project("__PROJECT_NAME__")
set_version("0.0.0")
set_license("GPL-3.0")
set_languages("c++23")
set_warnings("allextra")

-- add common rules
add_rules("mode.debug", "mode.releasedbg")
add_rules("plugin.vsxmake.autoupdate")

-- define targets
target("__PROJECT_NAME__")
    set_kind("shared")
    -- setup writes UTF-8; decode generated Windows resource strings the same way.
    add_mrcflags("/c65001", { force = true })

    add_rules("commonlibsse-ng.plugin", {
        name = "__PROJECT_NAME__",
        author = "hoskonen",
        description = "__PROJECT_DESCRIPTION__"
    })

    -- add src files
    add_files("src/**.cpp")
    add_headerfiles("src/**.h")
    add_includedirs("src")
    set_pcxxheader("src/pch.h")
