pipeline {
    agent any
    environment {
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        HARBOR_URL = "10.131.103.92:8090"
        HARBOR_PROJECT = "kp_4"
        TRIVY_OUTPUT_JSON = "trivy-output.json"
    }
    parameters {
        choice(
            name: 'ACTION',
            choices: ['FULL_PIPELINE', 'SCALE_ONLY'],
            description: 'Choose FULL_PIPELINE or SCALE_ONLY'
        )
          string(name: 'FRONTEND_REPLICA_COUNT', defaultValue: '1', description: 'Replica count for frontend')
          string(name: 'BACKEND_REPLICA_COUNT', defaultValue: '1', description: 'Replica count for backend')
          string(name: 'DB_REPLICA_COUNT', defaultValue: '1', description: 'Replica count for database')
    }
    stages {
        stage('Checkout') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                git 'https://github.com/ThanujaRatakonda/kp_4.git'
            }
        }
        stage('Build Docker Images') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def containers = [
                        [name: "frontend", folder: "frontend"],
                        [name: "backend", folder: "backend"]
                    ]
                    containers.each { c ->
                        echo "Building Docker image for ${c.name}..."
                        sh "docker build -t ${c.name}:${IMAGE_TAG} ./${c.folder}"
                    }
                }
            }
        }
        stage('Scan Docker Images') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def containers = ["frontend", "backend"]
                    containers.each { img ->
                        echo "Running Trivy scan for ${img}:${IMAGE_TAG}..."
                        sh """
                            trivy image ${img}:${IMAGE_TAG} \
                            --severity CRITICAL,HIGH \
                            --format json \
                            -o ${TRIVY_OUTPUT_JSON}
                        """
                        archiveArtifacts artifacts: "${TRIVY_OUTPUT_JSON}", fingerprint: true
                        def vulnerabilities = sh(script: """
                            jq '[.Results[] |
                                 (.Packages // [] | .[]? | select(.Severity=="CRITICAL" or .Severity=="HIGH")) +
                                 (.Vulnerabilities // [] | .[]? | select(.Severity=="CRITICAL" or .Severity=="HIGH"))
                                ] | length' ${TRIVY_OUTPUT_JSON}
                        """, returnStdout: true).trim()
                        if (vulnerabilities.toInteger() > 0) {
                            error "CRITICAL/HIGH vulnerabilities found in ${img}!"
                        }
                    }
                }
            }
        }
        stage('Push Images to Harbor') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    def containers = ["frontend", "backend"]
                    containers.each { img ->
                        def fullImage = "${HARBOR_URL}/${HARBOR_PROJECT}/${img}:${IMAGE_TAG}"
                        withCredentials([usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                            sh "echo \$HARBOR_PASS | docker login ${HARBOR_URL} -u \$HARBOR_USER --password-stdin"
                            sh "docker tag ${img}:${IMAGE_TAG} ${fullImage}"
                            sh "docker push ${fullImage}"
                        }
                        sh "docker rmi ${img}:${IMAGE_TAG} || true"
                    }
                }
            }
        }
        stage('Apply Kubernetes Deployment') {
            when { expression { params.ACTION == 'FULL_PIPELINE' } }
            steps {
                script {
                    
                    sh """
                        sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/frontend-deployment.yaml
                        sed -i 's/__IMAGE_TAG__/${IMAGE_TAG}/g' k8s/backend-deployment.yaml
                    """
                    
                    sh """
                        kubectl delete deployment frontend --ignore-not-found
                        kubectl delete deployment backend  --ignore-not-found
                        kubectl delete statefulset database --ignore-not-found
                        kubectl delete service frontend --ignore-not-found
                        kubectl delete service backend  --ignore-not-found
                        kubectl delete service database --ignore-not-found
                        kubectl get pvc shared-pvc || kubectl apply -f k8s/shared-pvc.yaml
                    """
                    // Apply new configurations
                    sh "kubectl apply -f k8s/"
                }
            }
        }
        stage('Scale Deployments') {
            steps {
                script {
                    sh "kubectl scale deployment frontend --replicas=${params.FRONTEND_REPLICA_COUNT}"
                    sh "kubectl scale deployment backend --replicas=${params.BACKEND_REPLICA_COUNT}"
                    sh "kubectl scale statefulset database --replicas=${params.DB_REPLICA_COUNT}"
                    sh "kubectl get deployments"
                }
            }
        }
    }
}
