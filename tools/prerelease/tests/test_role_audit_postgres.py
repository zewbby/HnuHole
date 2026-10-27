"""Exercise the real prerelease audit using two newly owned PostgreSQL clusters."""
import importlib.util
import os
from pathlib import Path
import secrets
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prerelease_environment', Path(__file__).parents[1] / 'environment.py')
environment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(environment)


@unittest.skipUnless(os.environ.get('PRERELEASE_AUDIT_SQL_TEST') == '1', 'owned PostgreSQL audit opt-in absent')
class PrereleaseRoleAuditPostgresTest(unittest.TestCase):
    def setUp(self):
        if os.name != 'posix' or os.geteuid() == 0:
            self.fail('requires a non-root Linux user for owned PostgreSQL')
        temporary = Path(tempfile.mkdtemp(prefix='hnuhole-prerelease-audit-'))
        root = temporary / 'lab'
        source = Path(__file__).resolve().parents[3]
        self.lab = environment.Lab(root, source)
        root.mkdir(mode=0o700)
        (root / 'material/operator').mkdir(parents=True, mode=0o700)
        ports = environment.free_ports(2)
        self.lab.state = dict(marker=environment.MARKER, source=str(source), target='source',
                              tag='hnuhole_runtime_prerelease_audit', processes={},
                              pgPorts={'source': dict(zip('cv', ports))})
        self.lab.save()
        def cleanup():
            # Retain the owned directory if PostgreSQL cannot be proven stopped.
            self.lab.stop()
            shutil.rmtree(temporary)
        self.addCleanup(cleanup)
        for party in 'cv':
            for role in ('runtime', 'migrator', 'recovery'):
                directory = root / 'material' if role == 'runtime' else root / 'material/operator'
                password = directory / ('db-' + party + '-' + role + '.password')
                password.write_text(secrets.token_hex(32))
                password.chmod(0o600)
            self.lab.init_cluster('source', party)
            migrations = source / 'services/api' / ('migrations' if party == 'c' else 'verifier-migrations')
            self.lab.run(['goose', '-dir', migrations, 'postgres', self.lab.dsn(party, 'migrator'), 'up'],
                         'migrate-' + party, env=self.lab.password_env(party, 'migrator'))
            self.lab.grants(party)

    def test_cleanup_grants_pass_and_extra_dm_permissions_fail(self):
        self.lab.audit()
        for role, privilege, table in [
            ('hnuhole_c_runtime', 'UPDATE(evidence_digest)', 'messages'),
            ('hnuhole_c_runtime', 'UPDATE', 'messages'),
            ('hnuhole_c_runtime', 'INSERT', 'messages'),
            ('hnuhole_c_runtime', 'SELECT', 'commands'),
            ('hnuhole_c_runtime', 'DELETE', 'messages'),
            ('hnuhole_c_runtime', 'UPDATE(peer_account)', 'blocks'),
            ('hnuhole_c_recovery', 'SELECT', 'messages'),
            ('hnuhole_business', 'SELECT', 'blocks'),
        ]:
            with self.subTest(role=role, privilege=privilege, table=table):
                self.lab.sql('c', 'GRANT ' + privilege + ' ON c_dm.' + table + ' TO ' + role)
                try:
                    with self.assertRaisesRegex(RuntimeError, 'owned SQL operation failed'):
                        self.lab.audit()
                    self.assertIn('operational role acquired noncontract table privilege',
                                  (self.lab.root / 'sql-error.private.log').read_text())
                finally:
                    self.lab.sql('c', 'REVOKE ' + privilege + ' ON c_dm.' + table + ' FROM ' + role)
                    # Table-level REVOKE UPDATE also removes lifecycle column grants.
                    self.lab.grants('c')
                self.lab.audit()

    def test_repost_grants_pass_and_extra_permissions_fail(self):
        self.lab.audit()
        for table in ('post_reposts', 'post_repost_versions'):
            for privilege in ('SELECT', 'INSERT', 'DELETE'):
                self.assertEqual(self.lab.sql('c', "SELECT has_table_privilege('hnuhole_c_runtime',"
                                              "'c_posts." + table + "','" + privilege + "')"), 't')
        self.assertEqual(self.lab.sql('c', "SELECT has_column_privilege('hnuhole_c_runtime',"
                                      "'c_posts.post_repost_versions','version','UPDATE')"), 't')
        self.assertEqual(self.lab.sql('c', "SELECT has_sequence_privilege('hnuhole_c_runtime',"
                                      "'c_posts.post_reposts_ordinal_seq','USAGE')"), 't')
        for role, privilege, relation, error in [
            ('hnuhole_c_runtime', 'UPDATE', 'post_repost_versions', 'table'),
            ('hnuhole_c_runtime', 'UPDATE(account_id)', 'post_repost_versions', 'table'),
            ('hnuhole_c_runtime', 'UPDATE(post_id)', 'post_repost_versions', 'table'),
            ('hnuhole_c_runtime', 'UPDATE', 'post_reposts', 'table'),
            ('hnuhole_c_runtime', 'UPDATE(identity_id)', 'post_reposts', 'table'),
            ('hnuhole_c_runtime', 'TRUNCATE', 'post_reposts', 'table'),
            ('hnuhole_c_runtime', 'TRUNCATE', 'post_repost_versions', 'table'),
            ('hnuhole_c_runtime', 'REFERENCES(post_id)', 'post_reposts', 'table'),
            ('hnuhole_c_runtime', 'TRIGGER', 'post_reposts', 'table'),
            ('hnuhole_c_recovery', 'SELECT', 'post_reposts', 'table'),
            ('hnuhole_c_recovery', 'SELECT', 'post_repost_versions', 'table'),
            ('hnuhole_business', 'SELECT', 'post_reposts', 'table'),
            ('hnuhole_business', 'SELECT', 'post_repost_versions', 'table'),
            ('hnuhole_c_runtime', 'SELECT', 'SEQUENCE post_reposts_ordinal_seq', 'sequence'),
            ('hnuhole_c_runtime', 'UPDATE', 'SEQUENCE post_reposts_ordinal_seq', 'sequence'),
            ('hnuhole_c_recovery', 'USAGE', 'SEQUENCE post_reposts_ordinal_seq', 'sequence'),
            ('hnuhole_business', 'USAGE', 'SEQUENCE post_reposts_ordinal_seq', 'sequence'),
        ]:
            with self.subTest(role=role, privilege=privilege, relation=relation):
                target = ('SEQUENCE c_posts.' + relation.removeprefix('SEQUENCE ')
                          if relation.startswith('SEQUENCE ') else 'c_posts.' + relation)
                self.lab.sql('c', 'GRANT ' + privilege + ' ON ' + target + ' TO ' + role)
                try:
                    with self.assertRaisesRegex(RuntimeError, 'owned SQL operation failed'):
                        self.lab.audit()
                    self.assertIn('operational role acquired noncontract ' + error + ' privilege',
                                  (self.lab.root / 'sql-error.private.log').read_text())
                finally:
                    self.lab.sql('c', 'REVOKE ' + privilege + ' ON ' + target + ' FROM ' + role)
                    # REVOKE UPDATE also removes the legitimate version grant.
                    self.lab.grants('c')
                self.lab.audit()

    def test_notification_grants_reject_recipient_mutation_and_trigger_execute(self):
        self.lab.audit()
        for role, privilege, target in [
            ('hnuhole_c_runtime', 'INSERT', 'c_inbox.records'),
            ('hnuhole_c_runtime', 'UPDATE(account_id)', 'c_inbox.records'),
            ('hnuhole_c_runtime', 'UPDATE', 'c_inbox.like_events'),
            ('hnuhole_c_recovery', 'SELECT', 'c_inbox.records'),
            ('hnuhole_business', 'SELECT', 'c_inbox.like_events'),
            ('hnuhole_c_runtime', 'UPDATE(account_id)', 'c_moderation.notifications'),
            ('hnuhole_c_runtime', 'EXECUTE', 'FUNCTION c_inbox.like_changed()'),
            ('PUBLIC', 'EXECUTE', 'FUNCTION c_inbox.comment_published()'),
        ]:
            with self.subTest(role=role, privilege=privilege, target=target):
                self.lab.sql('c', 'GRANT ' + privilege + ' ON ' + target + ' TO ' + role)
                try:
                    with self.assertRaisesRegex(RuntimeError, 'owned SQL operation failed'):
                        self.lab.audit()
                finally:
                    self.lab.sql('c', 'REVOKE ' + privilege + ' ON ' + target + ' FROM ' + role)
                    self.lab.grants('c')
                self.lab.audit()

    def test_restore_rebuilds_private_identity_avatar_function_acls(self):
        public_execute = """SELECT count(*) FROM pg_proc p
            JOIN pg_namespace n ON n.oid=p.pronamespace,
            LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
            WHERE ((n.nspname='public'
            AND p.proname IN ('guard_identity_avatar','bind_identity_avatar','close_identity_avatars'))
            OR n.nspname='c_inbox')
            AND a.grantee=0 AND a.privilege_type='EXECUTE'"""
        self.assertEqual(self.lab.sql('c', public_execute), '0')
        backup = self.lab.root / 'c.dump'
        self.lab.run(['pg_dump', '--format=custom', '--no-owner', '--no-privileges',
                      '--file', backup, self.lab.dsn('c', 'migrator')],
                     'avatar-acl-backup', env=self.lab.password_env('c', 'migrator'))
        self.lab.state['pgPorts']['restore'] = {'c': environment.free_ports(1)[0]}
        self.lab.save()
        self.lab.init_cluster('restore', 'c')
        self.lab.run(['pg_restore', '--exit-on-error', '--no-owner', '--no-privileges',
                      '--dbname', self.lab.dsn('c', 'migrator', 'restore'), backup],
                     'avatar-acl-restore', env=self.lab.password_env('c', 'migrator'))
        # Restored functions regain PostgreSQL's default PUBLIC EXECUTE.
        self.assertEqual(self.lab.sql('c', public_execute, target='restore'), '6')
        self.lab.grants('c', target='restore')
        self.assertEqual(self.lab.sql('c', public_execute, target='restore'), '0')


if __name__ == '__main__':
    unittest.main()
