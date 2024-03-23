from ci_core import Tests, Test, Client

client = Client('localhost', 4444)

tests = Tests(client, "Tests")
tests.add(Test("Test_1", "shadok"))
tests.add(Test("Test_2", "cmd_test"))

tests.run()

tests_2 = Tests(client, "Tests 2")
tests_2.add(Test("Test_1", "cmd_test"))
tests_2.add(Test("Test_2", "ultimate_answer"))

tests_2.run()
