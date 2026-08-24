import localUnitTest from './LocalUnit.test';
import apiClientTest from './ApiClient.test';

export default function testsuite() {
  localUnitTest();
  apiClientTest();
}