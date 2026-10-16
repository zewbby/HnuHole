"""Reject inflated closure claims, changed evidence and erased raw failures."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('closure', Path(__file__).parents[1] / 'check-non-ios-closure.py')
closure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(closure)


class CompletionTests(unittest.TestCase):
    def fixture(self, second=False):
        cases = [{'id': case, 'result': 'PASS' if second or case not in closure.SECOND_DEVICE_CASES else 'BLOCKED'}
                 for case in closure.CASE_IDS]
        return dict(cases=cases, checks=[dict(id=name, result='PASS', exitCode=0) for name in closure.REQUIRED_CHECKS],
                    unresolvedSecurityCriticalDefects=[], b6Result='PASS', b6WithoutSecondAndroidPassed=True,
                    nonIOSDevelopmentAcceptancePassed=second,
                    fixedCaseCounts=dict(PASS=24 if second else 22, FAIL=0, BLOCKED=0 if second else 2, NOT_RUN=0),
                    matrixResult='PASS' if second else 'BLOCKED', fullAnonymityClosurePassed=False,
                    productionApproved=False, fullDeviceMatrixPassed=False, iosAcceptancePassed=False,
                    futureBusinessAcceptancePassed=False, iosResult='SKIP', productionResult='NOT_RUN')

    def test_partial_and_complete_endpoints_are_derived_from_the_fixed_cases(self):
        self.assertEqual(closure.validate_completion(self.fixture())['BLOCKED'], 2)
        self.assertEqual(closure.validate_completion(self.fixture(second=True))['PASS'], 24)

    def test_missing_second_device_cannot_be_waived_or_hidden_in_claimed_counts(self):
        for change in [dict(nonIOSDevelopmentAcceptancePassed=True), dict(matrixResult='PASS'),
                       dict(fixedCaseCounts=dict(PASS=24, FAIL=0, BLOCKED=0, NOT_RUN=0))]:
            with self.subTest(change=change), self.assertRaises(AssertionError):
                value=self.fixture();value.update(change);closure.validate_completion(value)

    def test_missing_or_failed_final_regression_and_open_security_defect_block_closure(self):
        for mutation in ['missing', 'failed', 'boolean-exit', 'defect']:
            value=self.fixture(second=True)
            if mutation=='missing':value['checks'].pop()
            if mutation=='failed':value['checks'][0]['result']='FAIL'
            if mutation=='boolean-exit':value['checks'][0]['exitCode']=False
            if mutation=='defect':value['unresolvedSecurityCriticalDefects']=['authorization-defect']
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):closure.validate_completion(value)

    def test_duplicate_unknown_or_dropped_case_ids_never_make_a_new_denominator(self):
        for mutation in ['duplicate', 'unknown', 'missing']:
            value=self.fixture()
            if mutation=='duplicate':value['cases'][0]['id']=value['cases'][1]['id']
            if mutation=='unknown':value['cases'][0]['id']='NI-OPTIONAL01'
            if mutation=='missing':value['cases'].pop()
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):closure.validate_completion(value)

    def test_ios_production_or_future_business_cannot_be_promoted(self):
        for flag in ['fullAnonymityClosurePassed','productionApproved','fullDeviceMatrixPassed',
                     'iosAcceptancePassed','futureBusinessAcceptancePassed']:
            value=self.fixture();value[flag]=True
            with self.subTest(flag=flag), self.assertRaises(AssertionError):closure.validate_completion(value)


class EvidenceBoundaryTests(unittest.TestCase):
    def fixture(self):
        source=dict(caseId='NI-D02',result='PASS',apkSha256='ab'*32,rawAppFixtureResult='FAIL',
                    rawAppFixtureResultRewritten=False,independentSql=dict(result='PASS'),
                    independentProvider=dict(result='PASS',rejectionCode=50152,scope='DIRECT_PROVIDER_REJECTION_ONLY',
                        sdkCancellationUsedAsDiagnosis=False,evidenceLines=[dict(sha256='cd'*32)],networkErrors=[]),
                    facts=dict(actualGoogleRpValidationRejected=True,samePositiveControlPassed=True,
                               noCProofSubmitted=True,noPasskeyAdded=True))
        case=dict(id='NI-D02',result='PASS',moduleIds=['N03'],historicalVersionRewritten=False,
                  dependencyId='negative',pointer='/cases/0',boundary='DIRECT_PROVIDER_AND_ACTUAL_PRODUCT_SQL',apkSha256='ab'*32)
        return case,dict(negative=dict(cases=[source],originalUnknownResolved=False))

    def test_direct_provider_boundary_preserves_the_actual_sdk_failure(self):
        case,deps=self.fixture();closure.validate_case(case,deps,{'N03'})

    def test_sdk_cancellation_transport_error_or_missing_sql_does_not_supply_rejection(self):
        for mutation in ['sdk-only','transport','sql','wrong-code','unknown','changed-apk','erased-failure']:
            case,deps=self.fixture();source=deps['negative']['cases'][0]
            if mutation=='sdk-only':source['independentProvider']['sdkCancellationUsedAsDiagnosis']=True
            if mutation=='transport':source['independentProvider']['networkErrors']=['ERR_TIMED_OUT']
            if mutation=='sql':source['independentSql']['result']='NOT_RUN'
            if mutation=='wrong-code':source['independentProvider']['rejectionCode']=16
            if mutation=='unknown':deps['negative']['originalUnknownResolved']=True
            if mutation=='changed-apk':case['apkSha256']='ef'*32
            if mutation=='erased-failure':source['rawAppFixtureResult']='PASS'
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):closure.validate_case(case,deps,{'N03'})

    def test_emulator_cannot_supply_second_physical_android_evidence(self):
        source=dict(result='PASS',physicalAndroidDevices=[dict(id='phone',isPhysicalAndroid=True,isEmulator=False),
                   dict(id='emulator',isPhysicalAndroid=False,isEmulator=True)],actualApp=True,actualCV=True,
                   independentSqlVerified=True,actualOemTransfer=True)
        case=dict(id='NI-X01',result='PASS',moduleIds=['N01'],historicalVersionRewritten=False,
                  dependencyId='second',pointer='/cases/0',boundary='SECOND_PHYSICAL_ANDROID')
        with self.assertRaises(AssertionError):closure.validate_case(case,dict(second=dict(cases=[source])),{'N01'})

    def test_local_missing_key_refusal_requires_exact_case_fact_zero_requests_and_unchanged_sql(self):
        key='ni-k01-no-key';version=dict(pid=10,apkSha256='ab'*32)
        source=dict(caseId='NI-K01',result='PASS',stageKeys=[key])
        stage=dict(actualApp=dict(pid=10,actualApp=True,nativeVault=True,actualCV=False,actualProductReadOverwriteAndAuthorityRejected=True),
                   independentDevice=dict(pid=10,result='PASS'),versionAtLaunch=dict(capturedAtLaunch=True,apkSha256='ab'*32),
                   independentSqlAndProxy=dict(result='PASS',delta=dict(sessionReads=0),before=dict(sql=dict(activeSessions=1)),
                                              after=dict(sql=dict(activeSessions=1)),sqlReadOnly=True))
        case=dict(id='NI-K01',result='PASS',moduleIds=['N01'],historicalVersionRewritten=False,
                  boundary='B3_B4_ACTUAL_APP_DEVICE_SQL',dependencyId='historical',pointer='/phases/0',
                  stageKeys=[key],stageVersions={key:version},stageEvidenceDependencyId='matrix',stageEvidencePointer='/stages')
        deps=dict(historical=dict(phases=[source],acceptedStageVersions={key:version}),matrix=dict(stages={key:stage}))
        closure.validate_case(case,deps,{'N01'})
        for mutation in ['other-case','network','sql','missing-fact','claimed-cv']:
            value=copy.deepcopy(deps);record=copy.deepcopy(case);current=value['matrix']['stages'][key]
            if mutation=='other-case':record['id']='NI-D04';value['historical']['phases'][0]['caseId']='NI-D04'
            if mutation=='network':current['independentSqlAndProxy']['delta']['sessionReads']=1
            if mutation=='sql':current['independentSqlAndProxy']['after']['sql']['activeSessions']=2
            if mutation=='missing-fact':current['actualApp']['actualProductReadOverwriteAndAuthorityRejected']=False
            if mutation=='claimed-cv':current['actualApp']['actualCV']=True
            with self.subTest(mutation=mutation),self.assertRaises(AssertionError):closure.validate_case(record,value,{'N01'})

    def test_changed_dependency_hash_and_path_escape_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);path=root/'evidence.json';path.write_bytes(b'{"result":"PASS"}\n')
            ref=dict(path=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(closure.read_reference(root,ref)['result'],'PASS')
            published=path.read_bytes().replace(b'\n',b'\r\n')
            portable=dict(path=path.name,sha256=hashlib.sha256(published).hexdigest(),lfSha256=ref['sha256'])
            self.assertEqual(closure.read_reference(root,portable)['result'],'PASS')
            self.assertTrue(closure.matches_text_digest(published,portable['sha256'],portable['lfSha256']))
            path.write_text('{"result":"FAIL"}\n')
            with self.assertRaises(AssertionError):closure.read_reference(root,ref)
            with self.assertRaises(AssertionError):closure.read_reference(root,portable)
            with self.assertRaises(AssertionError):closure.repository_path(root,'../'+root.name+'/../')


if __name__=='__main__':unittest.main()
