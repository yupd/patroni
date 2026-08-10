"""
Database flavor naming convention module.

Centralizes all PostgreSQL vs Kingbase naming differences for files, directories,
binaries, and process identifiers. This allows Patroni to support multiple database
flavors without scattering platform checks throughout the codebase.

Supported flavors:
    - ``postgresql`` (default): Standard PostgreSQL naming conventions
    - ``kingbase``: KingbaseES V8 naming conventions
"""

from typing import Dict


class FlavorNaming:
    """Database flavor naming convention provider.

    Each flavor defines a mapping of canonical keys to platform-specific names.
    Code references canonical keys (e.g. ``version_file``) and this class returns
    the appropriate name for the configured flavor.

    Canonical key reference:
        - ``version_file``: Version indicator file in data directory
        - ``control_file``: pg_controldata/sys_controldata checkpoint file
        - ``pid_file``: Postmaster process ID file
        - ``conf_file``: Main configuration file (postgresql.conf / kingbase.conf)
        - ``auto_conf_file``: Auto-generated configuration file
        - ``hba_file``: Host-based authentication file
        - ``ident_file``: Ident configuration file
        - ``wal_dir_prefix``: WAL directory prefix (pg_ or sys_)
        - ``replslot_dir``: Replication slot directory name
        - ``tblspc_dir``: Tablespace directory name
        - ``postmaster_exe``: Acceptable postmaster executable names
        - ``proc_prefix``: Process command-line prefix for aux process detection
        - ``bin_name_map``: Default binary name mappings (pg_ctl -> sys_ctl, etc.)
        - ``config_base_name``: Config file base name
    """

    _NAMING: Dict[str, Dict[str, object]] = {
        'postgresql': {
            'version_file': 'PG_VERSION',
            'control_file': 'pg_control',
            'pid_file': 'postmaster.pid',
            'opts_file': 'postmaster.opts',
            'conf_file': 'postgresql.conf',
            'auto_conf_file': 'postgresql.auto.conf',
            'hba_file': 'pg_hba.conf',
            'ident_file': 'pg_ident.conf',
            'wal_dir_prefix': 'pg_',
            'replslot_dir': 'pg_replslot',
            'tblspc_dir': 'pg_tblspc',
            'stat_tmp_dir': 'pg_stat_tmp',
            'postmaster_exe': frozenset(['postgres', 'postmaster']),
            'proc_prefix': 'postgres:',
            'bin_name_map': {
                'postgres': 'postgres',
                'pg_ctl': 'pg_ctl',
                'initdb': 'initdb',
                'pg_isready': 'pg_isready',
                'pg_controldata': 'pg_controldata',
                'pg_rewind': 'pg_rewind',
                'pg_waldump': 'pg_waldump',
                'pg_basebackup': 'pg_basebackup',
                'psql': 'psql',
            },
            'config_base_name': 'postgresql',
        },
        'kingbase': {
            'version_file': 'SYS_VERSION',
            'control_file': 'sys_control',
            'pid_file': 'kingbase.pid',
            'opts_file': 'kingbase.opts',
            'conf_file': 'kingbase.conf',
            'auto_conf_file': 'kingbase.auto.conf',
            'hba_file': 'sys_hba.conf',
            'ident_file': 'sys_ident.conf',
            'wal_dir_prefix': 'sys_',
            'replslot_dir': 'sys_replslot',
            'tblspc_dir': 'sys_tblspc',
            'stat_tmp_dir': 'sys_stat_tmp',
            'postmaster_exe': frozenset(['kingbase', 'postmaster']),
            'proc_prefix': 'kingbase:',
            'bin_name_map': {
                'postgres': 'kingbase',
                'pg_ctl': 'sys_ctl',
                'initdb': 'initdb',
                'pg_isready': 'sys_isready',
                'pg_controldata': 'sys_controldata',
                'pg_rewind': 'sys_rewind',
                'pg_waldump': 'sys_waldump',
                'pg_basebackup': 'sys_basebackup',
                'psql': 'ksql',
            },
            'config_base_name': 'kingbase',
        },
    }

    def __init__(self, flavor: str = 'postgresql') -> None:
        """Initialize naming provider for a specific database flavor.

        :param flavor: One of ``'postgresql'`` (default) or ``'kingbase'``.
        """
        if flavor not in self._NAMING:
            raise ValueError(
                f"Unsupported database flavor '{flavor}'. "
                f"Supported flavors: {list(self._NAMING.keys())}"
            )
        self._flavor = flavor
        self._naming = self._NAMING[flavor]

    @property
    def flavor(self) -> str:
        """Current database flavor name."""
        return self._flavor

    def get(self, key: str) -> str:
        """Get a naming value by canonical key.

        :param key: Canonical naming key (e.g. ``'version_file'``, ``'pid_file'``).
        :returns: Platform-specific name for the given key.
        """
        if key not in self._naming:
            raise KeyError(f"Unknown naming key '{key}'")
        return str(self._naming[key])

    def get_bin_name(self, canonical_name: str) -> str:
        """Get a binary name for a canonical command.

        :param canonical_name: Canonical command name (e.g. ``'pg_ctl'``, ``'postgres'``).
        :returns: Platform-specific binary name.
        """
        bin_map = self._naming['bin_name_map']
        if isinstance(bin_map, dict):
            return bin_map.get(canonical_name, canonical_name)
        return canonical_name

    @property
    def version_file(self) -> str:
        """Version indicator file name (PG_VERSION / SYS_VERSION)."""
        return str(self._naming['version_file'])

    @property
    def control_file(self) -> str:
        """Control data file name (pg_control / sys_control)."""
        return str(self._naming['control_file'])

    @property
    def pid_file(self) -> str:
        """Postmaster PID file name."""
        return str(self._naming['pid_file'])

    @property
    def opts_file(self) -> str:
        """Postmaster opts file name."""
        return str(self._naming['opts_file'])

    @property
    def conf_file(self) -> str:
        """Main configuration file name."""
        return str(self._naming['conf_file'])

    @property
    def auto_conf_file(self) -> str:
        """Auto configuration file name."""
        return str(self._naming['auto_conf_file'])

    @property
    def hba_file(self) -> str:
        """HBA configuration file name."""
        return str(self._naming['hba_file'])

    @property
    def ident_file(self) -> str:
        """Ident configuration file name."""
        return str(self._naming['ident_file'])

    @property
    def wal_dir_prefix(self) -> str:
        """WAL directory prefix (pg_ / sys_)."""
        return str(self._naming['wal_dir_prefix'])

    @property
    def replslot_dir(self) -> str:
        """Replication slot directory name."""
        return str(self._naming['replslot_dir'])

    @property
    def tblspc_dir(self) -> str:
        """Tablespace directory name."""
        return str(self._naming['tblspc_dir'])

    @property
    def stat_tmp_dir(self) -> str:
        """Statistics temp directory name."""
        return str(self._naming['stat_tmp_dir'])

    @property
    def postmaster_exe(self) -> frozenset:
        """Set of acceptable postmaster executable names."""
        return self._naming['postmaster_exe']  # type: ignore[return-value]

    @property
    def proc_prefix(self) -> str:
        """Process command-line prefix for auxiliary process detection."""
        return str(self._naming['proc_prefix'])

    @property
    def config_base_name(self) -> str:
        """Config file base name (without .conf suffix)."""
        return str(self._naming['config_base_name'])
