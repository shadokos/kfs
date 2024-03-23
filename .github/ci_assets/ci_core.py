from typing import Union, List
import socket
import json
import sys
import os

import logging
from logging import DEBUG, INFO, WARNING, ERROR, CRITICAL

class Logger(logging.Logger):
    instance: logging.Logger = None

    def __new__(cls, *args, **kwargs):
        if cls.instance is None:
            cls.instance = super().__new__(cls)
        return cls.instance

    def __init__(self, *args, filename=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.level = kwargs.get("level", logging.INFO)
        self.handler = logging.StreamHandler() if filename is None else logging.FileHandler(filename)
        self.handler.setLevel(self.level)
        self.handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s [%(levelname)s]: %(message)s'))
        self.addHandler(self.handler)

    def debug(self, msg, *args, **kwargs):
        super().debug(msg, *args, **kwargs)

    def info(self, msg, *args, **kwargs):
        super().info(msg, *args, **kwargs)

    def warning(self, msg, *args, **kwargs):
        super().warning(msg, *args, **kwargs)

    def error(self, msg, *args, **kwargs):
        super().error(msg, *args, **kwargs)

    def critical(self, msg, *args, **kwargs):
        super().critical(msg, *args, **kwargs)

class Buffer:
    def __init__(self, socket: socket):
        self.buffer = b''
        self.socket = socket

    def read_delimiter(self, delimiter: bytes | str = b'\n') -> bytes | None:
        while delimiter not in self.buffer:
            data = self.socket.recv(4096)
            if not data:
                raise EOFError
            else:
                self.buffer += data
        line, delimiter, self.buffer = self.buffer.partition(delimiter)
        return line


class Client:
    def __init__(self, host: str = 'localhost', port: int = 4444, delimiter: bytes = b'\n'):
        self.socket: socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((host, port))
        self.buffer: Buffer = Buffer(self.socket)
        self.delimiter = delimiter

    def send(self, data: Union[bytes, str]):
        if isinstance(data, str):
            data = data.encode()
        self.socket.send(data + self.delimiter)

    def receive(self) -> Union[bytes, None]:
        data = self.buffer.read_delimiter(self.delimiter)
        #if data is not None:
        #    print(f'Received {data}')
        return data

class Test:
    def __init__(self, name: str, command: str):
        self.name = name
        self.command = command

class Tests:
    def __init__(self, client: Client, namespace: str):
        self.client: Client = client
        self.namespace: str = namespace
        self.logger = Logger(namespace)
        self.tests = []
        self.logger.info(f"namespace \"{namespace}\" initialized..")

    def add(self, test: Test):
        self.tests.append(test)

    def run(self):
        for test in self.tests:
            self.logger.info(f'Running {test.name} (command: \"{test.command}\")')
            if not self.run_test(test):
                self.quit()
            print()

    def quit(self):
        self.client.send("quit")
        exit(1)

    def run_test(self, test: Test) -> bool:
        self.client.send(test.command)
        cmd_logger = Logger(f'{self.namespace} ({test.name})')
        while True:
            try:
                raw_data = self.client.receive()
                data = json.loads(raw_data)

                if isinstance(data, dict) and data.get('type', None) is not None:
                    match data['type']:
                        case "Error":
                            self.logger.error(f"Test KO: {data['err']} (data: {data['data']})")
                            return False
                        case "Success":
                            self.logger.info("Test OK")
                            return True
                        case "Info":
                            self.logger.info(data['data'])
                else:
                    self.logger.info(raw_data.decode())
            except (socket.error, os.error, EOFError) as e:
                self.logger.error(f"Failed to receive data, exiting...")
                return False
            except ValueError:
                self.logger.info(raw_data.decode('UTF-8'))


