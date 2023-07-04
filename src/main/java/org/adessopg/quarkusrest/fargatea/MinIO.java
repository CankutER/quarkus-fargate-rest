package org.adessopg.quarkusrest.fargatea;

import io.minio.*;
import io.minio.errors.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import java.io.IOException;
import java.io.InputStream;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;


@ApplicationScoped
public class MinIO {
    @Inject
    MinioClient minIOClient;

    /*MinIO(){
        try {
        createBucket();

        } catch (Exception err){
            System.out.println(err.getMessage());
        }

    }*/


    public void createBucket() throws  IOException, NoSuchAlgorithmException, InvalidKeyException {
        try {
            boolean found = minIOClient.bucketExists(BucketExistsArgs.builder().bucket("adessopg-users").build());
            if(!found){
                minIOClient.makeBucket(MakeBucketArgs.builder().bucket("adessopg-users").build());
                System.out.println("Bucket created");
            }else {
                System.out.println("Bucket 'adessopg-users' already exists.");
            }
        } catch (MinioException err){
            System.out.println("Could not create or find the bucket");
            System.out.println(err.getMessage());
        }

    }
    public void uploadObject(String username) throws IOException {

        try{
            InputStream is=getClass().getResourceAsStream("/userpic.jpeg");
            System.out.println(is.available());
            if(is!=null) System.out.println("Stream is not null");
            if(minIOClient==null) System.out.println("Client is null");
            minIOClient.putObject(PutObjectArgs.builder().stream(is,-1,1024*1024*5).
                    object(username).bucket("adessopg-users").build());

        }catch (Exception err){
            System.out.println("Could not upload the file: "+err.getMessage());
            err.printStackTrace();
        }
    }

}


