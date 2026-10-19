"""Fail-closed bindings for delivery tools; no build or environment side effects."""
import os
from pathlib import Path

BASE='1a810944787eacb66e2115e1ce77de08190c366a'


def require(condition, message):
    if not condition:raise RuntimeError(message)


def bind_public_configuration(config, state, evidence, ca_pem):
    require(state.get('integrationScope')=='android-integration-20261019','wrong integration backend marker')
    require(state.get('sourceSha')==BASE and evidence.get('sourceSha')==BASE,'backend/evidence source mismatch')
    require(set(config)=={'communityOrigin','verifierOrigin','caPem'},'public configuration keys mismatch')
    require(config['communityOrigin']=='https://127.0.0.1:'+str(state['ports']['c']),'community origin is not this backend')
    require(config['verifierOrigin']=='https://127.0.0.1:'+str(state['ports']['v']),'verifier origin is not this backend')
    require(config['caPem']==ca_pem,'CA is not this backend trust root')


def owned_tool_environment(root, env):
    root=Path(root)
    require(os.name=='posix' and os.getuid()!=0,'non-root Linux tool environment required')
    require(root.is_absolute() and root==root.resolve() and root.is_dir() and not root.is_symlink(),'canonical explicit tool root required')
    require(root.stat().st_uid==os.getuid() and not root.stat().st_mode&0o077,'private owned tool root required')
    for name in ('GOCACHE','GOMODCACHE','GOPATH'):
        path=Path(env.get(name,''))
        require(path.is_absolute() and path==path.resolve() and path.is_relative_to(root) and path.is_dir(),'independent task cache required: '+name)
        require(path.stat().st_uid==os.getuid(),'cache owner mismatch: '+name)
    python=Path(env.get('PRERELEASE_IMAGE_PYTHON',''))
    require(python.is_absolute() and python.parent==python.parent.resolve() and python.parent.is_relative_to(root) and python.is_file(),'owned Pillow venv interpreter required')
    cfg=python.parent.parent/'pyvenv.cfg'
    require(cfg.is_file() and cfg.stat().st_uid==os.getuid(),'owned Python virtual environment required')
