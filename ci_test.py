import sys
import os

current_dir = os.path.dirname(__file__)
github_dir = os.path.join(current_dir, ".github/ci_assets")
sys.path.append(github_dir)

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
