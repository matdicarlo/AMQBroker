
package it.producer.ProducerService;

import org.apache.camel.ProducerTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
public class ProducerService {

    @Autowired
    private ProducerTemplate producerTemplate;

    private static final Logger log = LoggerFactory.getLogger(ProducerService.class);

    public void buildBody() throws Exception {
        String body = "test message";
        producerTemplate.sendBody("direct:message-producer", body);
    }
}
