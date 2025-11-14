import logging
import subprocess
import json
import os
from pygeoapi.process.base import BaseProcessor, ProcessorExecuteError

LOGGER = logging.getLogger(__name__)

script_title_and_path = __file__
metadata_title_and_path = script_title_and_path.replace('.py', '.json')
PROCESS_METADATA = json.load(open(metadata_title_and_path))

class WeightingFunctionsProcessor(BaseProcessor):

    def __init__(self, processor_def):
        super().__init__(processor_def, PROCESS_METADATA)
        self.supports_outputs = True
        self.my_job_id = 'nothing-yet'

    def set_job_id(self, job_id: str):
        self.my_job_id = job_id

    def __repr__(self):
        return f'<WeightingFunctionsProcessor> {self.name}'

    def execute(self, data, outputs=None):
        config_file_path = os.environ.get('DAUGAVA_CONFIG_FILE', "./pygeoapi/process/config.json")
        with open(config_file_path, 'r') as configFile:
            configJSON = json.load(configFile)

        download_dir = configJSON["download_dir"]
        own_url = configJSON["own_url"]

        # User inputs
        in_inputFile_tif = data.get('inputFile1_tif')
        in_inputFile_gpkg = data.get('inputFile2_gpkg')
        in_inputFile_dbf = data.get('inputFile3_dbf')

        # Check user inputs
        if in_inputFile_tif is None:
            raise ProcessorExecuteError('Missing parameter "inputFile1_tif". Please provide a inputFile1_tif.')
        if in_inputFile_gpkg is None:
            raise ProcessorExecuteError('Missing parameter "inputFile2_gpkg". Please provide a inputFile2_gpkg.')
        if in_inputFile_dbf is None:
            raise ProcessorExecuteError('Missing parameter "inputFile3_dbf". Please provide a inputFile3_dbf.')

        # Where to store output data
        downloadfilename1 = 'weight_table-%s.csv' % self.my_job_id
        downloadfilename2 = 'weight_table-%s.rds' % self.my_job_id

        returncode, stdout, stderr = run_docker_container(
            in_inputFile_tif,
            in_inputFile_gpkg,
            in_inputFile_dbf,
            download_dir, 
            downloadfilename1,
            downloadfilename2
        )

        if not returncode == 0:
            err_msg = 'Running docker container failed.'
            for line in stderr.split('\n'):
                if line.startswith('Error'):
                    err_msg = 'Running docker container failed: %s' % (line)
            raise ProcessorExecuteError(user_msg = err_msg)

        else:
            # Create download link:
            downloadlink1 = own_url.rstrip('/')+os.sep+downloadfilename1
            downloadlink2 = own_url.rstrip('/')+os.sep+downloadfilename2

            # Return link to file:
            response_object = {
                "outputs": {
                    "weight_table_csv": {
                        "title": self.metadata['outputs']['weight_table_csv']['title'],
                        "description": self.metadata['outputs']['weight_table_csv']['description'],
                        "href": f'{downloadlink1}'
                    },
                    "weight_table_rds": {
                        "title": self.metadata['outputs']['weight_table_rds']['title'],
                        "description": self.metadata['outputs']['weight_table_rds']['description'],
                        "href": f'{downloadlink2}'
                    }
                }
            }

            return 'application/json', response_object


def run_docker_container(
        in_inputFile_tif,
        in_inputFile_gpkg,
        in_inputFile_dbf,
        download_dir, 
        downloadfilename1,
        downloadfilename2
    ):
    LOGGER.debug('Start running docker container')
    container_name = f'aquainfra-elbe-usecase-image_{os.urandom(5).hex()}'
    image_name = 'aquainfra-elbe-usecase-image'

    # Mounting
    container_out = '/out'
    local_out = os.path.join(download_dir, "out")
    os.makedirs(local_out, exist_ok=True)

    script = 'weighting_functions.R'

    docker_command = [
        "sudo", "docker", "run", "--rm", "--name", container_name,
        "-v", f"{local_out}:{container_out}",
        "-e", f"R_SCRIPT={script}",
        image_name,
        in_inputFile_tif,
        in_inputFile_gpkg,
        in_inputFile_dbf,
        f"{container_out}/{downloadfilename1}",
        f"{container_out}/{downloadfilename2}"
    ]
    
    # Run container
    try:
        result = subprocess.run(docker_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout = result.stdout.decode()
        stderr = result.stderr.decode()
        return result.returncode, stdout, stderr

    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout.decode(), e.stderr.decode()