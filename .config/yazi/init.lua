-- gitp4v settings (yours; kept outside the plugin folder). The available options
-- and their defaults are documented in plugins/gitp4v.yazi/config.lua.
gitp4v_opts = {
	org = "AMD-GEIP",
	p4 = {
		port = "bdcp4p01.amd.com:1677",
		user = "petecook",
	},
	clones = "/proj/geip_users01/petecook/gitp4v",
	diff = "nvim -d",
}

-- >>> gitp4v (managed by plugins/gitp4v.yazi/install.sh) >>>
require("gitp4v"):setup(gitp4v_opts)
-- <<< gitp4v <<<
