import logging
import subprocess
import json
import os
from pygeoapi.process.base import BaseProcessor, ProcessorExecuteError

LOGGER = logging.getLogger(__name__)

script_title_and_path = __file__
metadata_title_and_path = script_title_and_path.replace('.py', '.json')
PROCESS_METADATA = json.load(open(metadata_title_and_path))

class CombineEurostatDataProcessor(BaseProcessor):

    def __init__(self, processor_def):
        super().__init__(processor_def, PROCESS_METADATA)
        self.supports_outputs = True
        self.my_job_id = 'nothing-yet'

    def set_job_id(self, job_id: str):
        self.my_job_id = job_id

    def __repr__(self):
        return f'<CombineEurostatDataProcessor> {self.name}'

    def execute(self, data, outputs=None):
        config_file_path = os.environ.get('DAUGAVA_CONFIG_FILE', "./config.json")
        with open(config_file_path, 'r') as configFile:
            configJSON = json.load(configFile)

        download_dir = configJSON["download_dir"]
        own_url = configJSON["own_url"]

        # User inputs
        in_country_code = data.get('country_code')
        in_year = data.get('year')

        # Check user inputs
        if in_country_code is None:
            raise ProcessorExecuteError('Missing parameter "inputFile_tif". Please provide a inputFile_tif.')
        if in_year is None:
            raise ProcessorExecuteError('Missing parameter "year". Please provide a year.')

        # Where to store output data
        downloadfilename = 'nuts3_pop_data-%s.gpkg' % self.my_job_id

        returncode, stdout, stderr = run_docker_container(
            in_country_code,
            in_year,
            download_dir, 
            downloadfilename
        )

        if not returncode == 0:
            err_msg = 'Running docker container failed.'
            for line in stderr.split('\n'):
                if line.startswith('Error'):
                    err_msg = 'Running docker container failed: %s' % (line)
            raise ProcessorExecuteError(user_msg = err_msg)

        else:
            # Create download link:
            downloadlink = own_url.rstrip('/')+os.sep+downloadfilename

            # Return link to file:
            response_object = {
                "outputs": {
                    "nuts3_pop_data": {
                        "title": self.metadata['outputs']['nuts3_pop_data']['title'],
                        "description": self.metadata['outputs']['nuts3_pop_data']['description'],
                        "href": f'{downloadlink}'
                    }
                }
            }

            return 'application/json', response_object


def run_docker_container(
        in_country_code,
        in_year,
        download_dir, 
        downloadfilename
    ):
    LOGGER.debug('Start running docker container')
    container_name = f'aquainfra-elbe-usecase-image_{os.urandom(5).hex()}'
    image_name = 'aquainfra-elbe-usecase-image'

    # Mounting
    container_out = '/out'
    local_out = os.path.join(download_dir, "out")
    os.makedirs(local_out, exist_ok=True)

    script = 'combine_eurostat_data.R'

    docker_command = [
        "sudo", "docker", "run", "--rm", "--name", container_name,
        "-v", f"{local_out}:{container_out}",
        "-e", f"R_SCRIPT={script}",
        image_name,
        in_country_code,
        in_year,
        f"{container_out}/{downloadfilename}"
    ]

    # Run container
    try:
        result = subprocess.run(docker_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout = result.stdout.decode()
        stderr = result.stderr.decode()
        return result.returncode, stdout, stderr

    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout.decode(), e.stderr.decode()