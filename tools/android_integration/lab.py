#!/usr/bin/env python3
"""Configured integration lab; inherits the prerelease lifecycle, not its old full rehearsal."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'prerelease'))
from environment import Lab, free_ports, sha, write  # noqa: E402
from policy import owned_tool_environment

BASE = '1a810944787eacb66e2115e1ce77de08190c366a'


class IntegrationLab(Lab):
    def dsn(self, party, role, target=None):
        return super().dsn(party, role, 'source' if party == 'v' else target)

    def sql(self, party, query, *, target=None, role='admin'):
        return super().sql(party, query, target='source' if party == 'v' else target, role=role)

    def pg_start(self, target, party):
        return super().pg_start('source' if party == 'v' else target, party)

    def grants(self, party, target=None):
        # Restore removes ACLs. Comments need the same PUBLIC EXECUTE deny
        # baseline as fresh migration, before canonical runtime opt-in grants.
        if party == 'c':
            self.sql('c', 'REVOKE ALL ON SCHEMA c_comments FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;'
                     'REVOKE ALL ON ALL TABLES IN SCHEMA c_comments FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;'
                     'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_comments FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;',
                     target=target, role='migrator')
        super().grants(party, target)
        if party == 'c':
            self.sql('c', (self.source / 'infra/postgres/grant-comments.sql').read_text(), target=target, role='migrator')

    def init_integration(self):
        if self.root.exists() or self.state is not None:
            raise RuntimeError('new task-owned root required')
        if os.geteuid() == 0 or str(self.root).startswith('/mnt/'):
            raise RuntimeError('non-root Linux filesystem required')
        owned_tool_environment(self.root.parent/'tools',os.environ)
        actual = subprocess.check_output(['git', '-C', self.source, 'rev-parse', 'HEAD'], text=True).strip()
        if actual != BASE or subprocess.check_output(['git', '-C', self.source, 'status', '--porcelain'], text=True).strip():
            raise RuntimeError('clean fixed integration product source required')
        self.root.mkdir(mode=0o700)
        for name in ('bin', 'probe-state', 'backup'):
            (self.root / name).mkdir(mode=0o700)
        ports = free_ports(9)
        self.state = dict(marker='hnuhole-android-prerelease-v1', integrationScope='android-integration-20261019',
                          source=str(self.source), sourceSha=BASE, tag='hnuhole_integration_' + secrets.token_hex(6),
                          ports=dict(zip(('c', 'v', 'ci', 'vi', 'smtp', 'mail'), ports[:6])),
                          pgPorts={'source':dict(zip('cv', ports[6:8])), 'restore':{'c':ports[8]}},
                          target='source', processes={})
        self.env['AUTHRUNTIME_TAG'] = self.state['tag']
        self.save()
        (self.root/'probe-state/.runtime-tag').write_text(self.state['tag'])
        self.build(self.source, 'candidate-')
        self.run(['go','build','-mod=readonly','-o',self.root/'bin/authdev','./cmd/authdev'],'build-authdev')
        args=[self.root/'bin/authdev','init','-dir',self.root/'material']
        for key,flag in [('c','community-port'),('v','verifier-port'),('ci','community-internal-port'),('vi','verifier-internal-port'),('smtp','smtp-port')]:
            args += ['-'+flag,self.state['ports'][key]]
        for party,flag in [('c','community-dsn'),('v','verifier-dsn')]:
            args += ['-'+flag,self.dsn(party,'runtime'),'-recovery-dsn' if party=='c' else '-verifier-recovery-dsn',self.dsn(party,'recovery')]
        self.run(args,'authdev-init')
        for party in 'cv':
            self.init_cluster('source',party)
            directory=self.api/('migrations' if party=='c' else 'verifier-migrations')
            self.run(['goose','-dir',directory,'postgres',self.dsn(party,'migrator'),'up'],'formal-migrate-'+party,env=self.password_env(party,'migrator'))
            self.grants(party)
        python=os.environ['PRERELEASE_IMAGE_PYTHON']
        if not Path(python).is_file():raise RuntimeError('owned Pillow interpreter required')
        validator=self.root/'validate_image.py'
        validator.write_bytes((self.api/'media/validate_image.py').read_bytes());validator.chmod(0o600)
        cpath=self.root/'material/c.json';config=json.loads(cpath.read_text())
        config['postImages']=dict(pythonFile=python,validatorFile=str(validator),validatorSHA256=sha(validator))
        config['moderation']=True
        config['adminDirectory']=str(self.source/'apps/admin')
        for name in ('comment-command.key','comment-fingerprint.key'):
            key=self.root/'material'/name;key.write_bytes(secrets.token_bytes(32));key.chmod(0o600)
        config['comments']=dict(commandKeyFile='comment-command.key',fingerprintKeyFile='comment-fingerprint.key')
        write(cpath,config)
        self.state['migrationSha256']={str(p.relative_to(self.api)):sha(p) for directory in ('migrations','verifier-migrations') for p in (self.api/directory).glob('*.sql')}
        self.save()
        self.audit()
        public=dict(communityOrigin='https://127.0.0.1:'+str(self.state['ports']['c']),
                    verifierOrigin='https://127.0.0.1:'+str(self.state['ports']['v']),
                    caPem=(self.root/'material/dev-ca.pem').read_text())
        write(self.root/'public-config.json',public)
        print('Configured fixed-schema18 C/V lab initialized; old rehearsal not run',flush=True)


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('command',choices=['init','start','health','stop','recover'])
    a=p.parse_args()
    if not a.root.is_absolute() or a.root!=a.root.resolve() or a.root.is_symlink():
        p.error('absolute canonical private task root required')
    lab=IntegrationLab(a.root,a.source.resolve())
    if a.command=='init':
        try:lab.init_integration()
        except Exception:
            if lab.state:lab.stop()
            raise
    elif not lab.state or lab.state.get('integrationScope')!='android-integration-20261019':
        p.error('initialized integration-owned lab required')
    elif a.command=='start':lab.start(watches=False)
    elif a.command=='recover':
        lab.halt(['watch-c','watch-v'])
        for party in 'cv':
            lab.operator('recover',party)
            lab.spawn('watch-'+party,[lab.root/'bin/authdev','watch','-operator',lab.root/'material/operator'/('operator.json' if party=='c' else 'v-operator.json')])
    else:getattr(lab,a.command)()


if __name__=='__main__':main()
