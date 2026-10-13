import importlib.util
from pathlib import Path
import unittest

p=Path(__file__).resolve().parents[1]/'verify-android-b3-b4-provider-rejection.py'
s=importlib.util.spec_from_file_location('provider',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)


class ProviderEvidenceTest(unittest.TestCase):
    def row(self, text, at=1791854625.0, pid=8195):
        return f'{at:.3f} {pid} {pid} W Auth.Api.Credentials: {text}'

    def log(self):
        return '\n'.join(self.row(x) for x in [m.VALIDATE,m.RP_ERROR,'at curi.g(public:10)','at aolv.a(public:25)',m.ERROR_END])

    def check(self, raw, native=None, **kw):
        return m.verify(raw,8195,1791854600,1791854670,native or {'pid':8896,'nativeBegun':1,'nativeErrored':1},**kw)

    def test_explicit_current_provider_rejection(self):
        self.assertEqual(self.check(self.log())['rejectionCode'],50152)

    def test_generic_cancel_and_message_without_validator_do_not_pass(self):
        for raw in [self.row(m.VALIDATE)+'\n'+self.row(m.ERROR_END), self.log().replace('at aolv.a(public:25)','unrelated')]:
            with self.assertRaises(ValueError):self.check(raw)

    def test_stale_or_wrong_process_evidence_is_refused(self):
        for raw in [self.log().replace('1791854625.000','1791854500.000'),self.log().replace('8195 8195','1234 1234')]:
            with self.assertRaises(ValueError):self.check(raw)

    def test_timeout_and_overlapping_requests_are_refused(self):
        with self.assertRaises(ValueError):self.check(self.log(),{'pid':8896,'nativeBegun':1,'nativeErrored':1,'nativeTimeout':1})
        with self.assertRaises(ValueError):self.check(self.log()+'\n'+self.row(m.VALIDATE))

    def test_transport_failure_cannot_accept_signature_negative(self):
        with self.assertRaises(ValueError):self.check(self.log()+'\n'+self.row('net::ERR_CONNECTION_TIMED_OUT'))

    def test_wrong_rp_hostname_failure_requires_separate_success(self):
        raw=self.log()+'\n'+self.row('net::ERR_CERT_COMMON_NAME_INVALID')+'\n'+self.row(m.VALIDATE,1791854631)+'\n'+self.row(m.SUCCESS_END,1791854641)
        native={'pid':8896,'nativeBegun':2,'nativeErrored':1,'nativeSucceeded':1}
        self.assertTrue(self.check(raw,native,server_followup=True)['correctRpFollowupSucceeded'])
        with self.assertRaises(ValueError):self.check(raw.replace(m.SUCCESS_END,m.ERROR_END),native,server_followup=True)


if __name__=='__main__':unittest.main()
